import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/languages.dart';
import '../core/toolchain.dart';
import '../workspace/editor_document.dart';
import '../workspace/workspace.dart';
import 'output_service.dart';

class LspCompletion {
  const LspCompletion({required this.label, this.detail, this.insertText, this.kind = 0, this.isSnippet = false});

  final String label;
  final String? detail;
  final String? insertText;

  /// LSP CompletionItemKind.
  final int kind;
  final bool isSnippet;
}

class LspLocation {
  const LspLocation(this.path, this.line, this.column);

  final String path;
  final int line;
  final int column;
}

class LspTextEdit {
  const LspTextEdit(this.startLine, this.startCol, this.endLine, this.endCol, this.newText);

  final int startLine, startCol, endLine, endCol;
  final String newText;
}

enum LspState { starting, ready, failed, stopped }

/// Minimal JSON-RPC Language Server Protocol client over stdio.
class LspClient {
  LspClient({required this.spec, required this.language, required this.rootPath, required this.output, required this.onDiagnostics, required this.onStateChanged});

  final LspSpec spec;
  final LanguageDef language;
  final String? rootPath;
  final OutputService output;
  final void Function(String path, List<Diagnostic> diags) onDiagnostics;
  final VoidCallback onStateChanged;

  Process? _proc;
  int _nextId = 1;
  final Map<int, Completer<dynamic>> _pending = {};
  final List<int> _buffer = [];
  LspState state = LspState.starting;
  Map<String, dynamic> capabilities = {};
  final Set<String> _openUris = {};

  String get channel => 'Language Server (${language.name})';

  Future<void> start() async {
    try {
      _proc = await Process.start(spec.command, spec.args, workingDirectory: rootPath, runInShell: Platform.isWindows);
    } catch (e) {
      state = LspState.failed;
      output.append(channel, 'Failed to start ${spec.command}: $e');
      onStateChanged();
      return;
    }
    _proc!.stdout.listen(_onData, onDone: () {
      state = LspState.stopped;
      onStateChanged();
    });
    _proc!.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((s) => output.append(channel, s));
    _proc!.exitCode.then((code) {
      output.append(channel, '${spec.command} exited with code $code');
      state = LspState.stopped;
      for (final Completer<dynamic> c in _pending.values) {
        if (!c.isCompleted) c.complete(null);
      }
      _pending.clear();
      onStateChanged();
    });
    final String? rootUri = rootPath == null ? null : Uri.file(rootPath!, windows: Platform.isWindows).toString();
    final dynamic result = await request('initialize', {
      'processId': pid,
      'clientInfo': {'name': 'SmartIDE', 'version': '1.0.0'},
      'rootUri': rootUri,
      'workspaceFolders': rootUri == null ? null : [
        {'uri': rootUri, 'name': rootPath!.split(Platform.pathSeparator).last},
      ],
      'capabilities': {
        'textDocument': {
          'synchronization': {'didSave': true, 'dynamicRegistration': false},
          'completion': {
            'completionItem': {'snippetSupport': true, 'documentationFormat': ['plaintext', 'markdown']},
            'contextSupport': true,
          },
          'hover': {'contentFormat': ['plaintext', 'markdown']},
          'definition': {'linkSupport': false},
          'formatting': {'dynamicRegistration': false},
          'publishDiagnostics': {'relatedInformation': false},
        },
        'workspace': {'workspaceFolders': true, 'configuration': true},
        'window': {'workDoneProgress': false},
      },
    }, timeout: const Duration(seconds: 30));
    if (result is Map) {
      capabilities = Map<String, dynamic>.from(result['capabilities'] as Map? ?? {});
      notify('initialized', {});
      state = LspState.ready;
      output.append(channel, '${spec.command} ready');
    } else {
      state = LspState.failed;
    }
    onStateChanged();
  }

  void _onData(List<int> data) {
    _buffer.addAll(data);
    while (true) {
      final int headerEnd = _indexOf(_buffer, const [13, 10, 13, 10]);
      if (headerEnd < 0) return;
      final String header = ascii.decode(_buffer.sublist(0, headerEnd), allowInvalid: true);
      final RegExpMatch? m = RegExp(r'Content-Length:\s*(\d+)', caseSensitive: false).firstMatch(header);
      if (m == null) {
        _buffer.removeRange(0, headerEnd + 4);
        continue;
      }
      final int len = int.parse(m.group(1)!);
      if (_buffer.length < headerEnd + 4 + len) return;
      final List<int> body = _buffer.sublist(headerEnd + 4, headerEnd + 4 + len);
      _buffer.removeRange(0, headerEnd + 4 + len);
      try {
        _onMessage(jsonDecode(utf8.decode(body, allowMalformed: true)) as Map<String, dynamic>);
      } catch (e) {
        output.append(channel, 'Bad message: $e');
      }
    }
  }

  static int _indexOf(List<int> data, List<int> pattern) {
    outer:
    for (int i = 0; i <= data.length - pattern.length; i++) {
      for (int j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  void _onMessage(Map<String, dynamic> msg) {
    if (msg.containsKey('id') && (msg.containsKey('result') || msg.containsKey('error')) && !msg.containsKey('method')) {
      final Completer<dynamic>? c = _pending.remove(msg['id']);
      if (msg['error'] != null) output.append(channel, 'Error: ${msg['error']}');
      c?.complete(msg['result']);
      return;
    }
    final String? method = msg['method'] as String?;
    final dynamic params = msg['params'];
    if (msg.containsKey('id')) {
      // Server -> client request. Answer the few we understand.
      dynamic result;
      if (method == 'workspace/configuration') {
        result = List<dynamic>.filled((params?['items'] as List?)?.length ?? 1, null);
      } else if (method == 'workspace/workspaceFolders') {
        result = rootPath == null ? null : [
          {'uri': Uri.file(rootPath!, windows: Platform.isWindows).toString(), 'name': 'root'},
        ];
      }
      _send({'jsonrpc': '2.0', 'id': msg['id'], 'result': result});
      return;
    }
    switch (method) {
      case 'textDocument/publishDiagnostics':
        final String uri = params['uri'] as String;
        final String path = Uri.parse(uri).toFilePath(windows: Platform.isWindows);
        final List<Diagnostic> diags = [
          for (final dynamic d in params['diagnostics'] as List)
            Diagnostic(
              severity: switch (d['severity']) {
                1 => DiagnosticSeverity.error,
                2 => DiagnosticSeverity.warning,
                3 => DiagnosticSeverity.info,
                _ => DiagnosticSeverity.hint,
              },
              message: '${d['message']}',
              line: d['range']['start']['line'] as int,
              column: d['range']['start']['character'] as int,
              endLine: d['range']['end']['line'] as int,
              endColumn: d['range']['end']['character'] as int,
              source: d['source'] as String?,
            ),
        ];
        onDiagnostics(path, diags);
      case 'window/logMessage':
      case 'window/showMessage':
        output.append(channel, '${params['message']}');
    }
  }

  void _send(Map<String, dynamic> msg) {
    final Process? proc = _proc;
    if (proc == null) return;
    final List<int> body = utf8.encode(jsonEncode(msg));
    try {
      proc.stdin.add(ascii.encode('Content-Length: ${body.length}\r\n\r\n'));
      proc.stdin.add(body);
    } catch (_) {}
  }

  Future<dynamic> request(String method, Map<String, dynamic> params, {Duration timeout = const Duration(seconds: 8)}) {
    final int id = _nextId++;
    final Completer<dynamic> c = Completer<dynamic>();
    _pending[id] = c;
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return c.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      return null;
    });
  }

  void notify(String method, Map<String, dynamic> params) => _send({'jsonrpc': '2.0', 'method': method, 'params': params});

  void didOpen(EditorDocument doc) {
    if (_openUris.contains(doc.uri)) return;
    _openUris.add(doc.uri);
    notify('textDocument/didOpen', {
      'textDocument': {'uri': doc.uri, 'languageId': _languageId(doc.language.id), 'version': doc.version, 'text': doc.text},
    });
  }

  void didChange(EditorDocument doc) {
    if (!_openUris.contains(doc.uri)) return didOpen(doc);
    notify('textDocument/didChange', {
      'textDocument': {'uri': doc.uri, 'version': doc.version},
      'contentChanges': [
        {'text': doc.text},
      ],
    });
  }

  void didSave(EditorDocument doc) => notify('textDocument/didSave', {
        'textDocument': {'uri': doc.uri},
        'text': doc.text,
      });

  void didClose(EditorDocument doc) {
    if (!_openUris.remove(doc.uri)) return;
    notify('textDocument/didClose', {
      'textDocument': {'uri': doc.uri},
    });
  }

  Map<String, dynamic> _pos(EditorDocument doc, int line, int col) => {
        'textDocument': {'uri': doc.uri},
        'position': {'line': line, 'character': col},
      };

  Future<List<LspCompletion>> completion(EditorDocument doc, int line, int col) async {
    final dynamic r = await request('textDocument/completion', _pos(doc, line, col), timeout: const Duration(seconds: 3));
    final List<dynamic> items = r is List ? r : (r is Map ? (r['items'] as List? ?? []) : []);
    return [
      for (final dynamic i in items.take(200))
        LspCompletion(
          label: '${i['label']}'.trim(),
          detail: i['detail'] as String?,
          insertText: (i['textEdit'] is Map ? i['textEdit']['newText'] : null) as String? ?? i['insertText'] as String?,
          kind: (i['kind'] as int?) ?? 0,
          isSnippet: i['insertTextFormat'] == 2,
        ),
    ];
  }

  Future<String?> hover(EditorDocument doc, int line, int col) async {
    final dynamic r = await request('textDocument/hover', _pos(doc, line, col));
    if (r is! Map) return null;
    final dynamic c = r['contents'];
    if (c is String) return c;
    if (c is Map) return '${c['value']}';
    if (c is List) return c.map((e) => e is Map ? e['value'] : '$e').join('\n\n');
    return null;
  }

  Future<LspLocation?> definition(EditorDocument doc, int line, int col) async {
    final dynamic r = await request('textDocument/definition', _pos(doc, line, col));
    final dynamic loc = r is List ? (r.isEmpty ? null : r.first) : r;
    if (loc is! Map) return null;
    final String uri = (loc['uri'] ?? loc['targetUri']) as String;
    final Map<dynamic, dynamic> range = (loc['range'] ?? loc['targetSelectionRange']) as Map;
    return LspLocation(
      Uri.parse(uri).toFilePath(windows: Platform.isWindows),
      (range['start']['line'] as int) + 1,
      (range['start']['character'] as int) + 1,
    );
  }

  Future<List<LspTextEdit>> format(EditorDocument doc, int tabSize, bool insertSpaces) async {
    final dynamic r = await request('textDocument/formatting', {
      'textDocument': {'uri': doc.uri},
      'options': {'tabSize': tabSize, 'insertSpaces': insertSpaces},
    });
    if (r is! List) return [];
    return [
      for (final dynamic e in r)
        LspTextEdit(
          e['range']['start']['line'] as int,
          e['range']['start']['character'] as int,
          e['range']['end']['line'] as int,
          e['range']['end']['character'] as int,
          e['newText'] as String,
        ),
    ];
  }

  Future<void> shutdown() async {
    if (state == LspState.ready) {
      await request('shutdown', {}, timeout: const Duration(seconds: 2));
      notify('exit', {});
    }
    _proc?.kill();
    state = LspState.stopped;
  }

  static String _languageId(String id) => switch (id) {
        'cpp' => 'cpp',
        'csharp' => 'csharp',
        'javascript' => 'javascript',
        'typescript' => 'typescript',
        'shell' => 'shellscript',
        _ => id,
      };
}

/// Starts language servers on demand and routes document events to them.
class LspService extends ChangeNotifier {
  LspService(this.workspace, this.output, this.isLanguageEnabled) {
    workspace.onDocumentOpened.add(_opened);
    workspace.onDocumentChanged.add(_changed);
    workspace.onDocumentSaved.add((d) => _clientFor(d)?.didSave(d));
    workspace.onDocumentClosed.add((d) => _clientFor(d)?.didClose(d));
  }

  final Workspace workspace;
  final OutputService output;
  final bool Function(LanguageDef lang) isLanguageEnabled;
  final Map<String, LspClient> _clients = {};
  final Set<String> _missing = {};
  final Map<String, Timer> _changeTimers = {};
  bool enabled = true;

  /// Languages whose server is not installed (shown as hints in the UI).
  Set<String> get missingServers => _missing;

  LspClient? clientForLanguage(String id) => _clients[id];

  String? _key(LanguageDef l) => l.lsp == null ? null : '${l.lsp!.command}:${l.id == 'c' ? 'cpp' : l.id}';

  LspClient? _clientFor(EditorDocument d) {
    final String? k = _key(d.language);
    return k == null ? null : _clients[k];
  }

  LspClient? clientFor(EditorDocument d) {
    final LspClient? c = _clientFor(d);
    return c?.state == LspState.ready ? c : null;
  }

  Future<void> _opened(EditorDocument d) async {
    if (!enabled || d.isUntitled) return;
    final LanguageDef l = d.language;
    final LspSpec? spec = l.lsp;
    final String? key = _key(l);
    if (spec == null || key == null || !isLanguageEnabled(l)) return;
    LspClient? c = _clients[key];
    if (c == null) {
      if (_missing.contains(key)) return;
      final String? exe = await Toolchain.which(spec.command);
      if (exe == null) {
        _missing.add(key);
        output.append('SmartIDE', '${l.name}: language server "${spec.command}" not found. Install: ${spec.installHint}');
        notifyListeners();
        return;
      }
      c = LspClient(
        spec: spec,
        language: l,
        rootPath: workspace.root,
        output: output,
        onDiagnostics: workspace.setDiagnostics,
        onStateChanged: notifyListeners,
      );
      _clients[key] = c;
      notifyListeners();
      await c.start();
    }
    while (c.state == LspState.starting) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (c.state == LspState.ready) c.didOpen(d);
  }

  void _changed(EditorDocument d) {
    final LspClient? c = clientFor(d);
    if (c == null) return;
    _changeTimers[d.id]?.cancel();
    _changeTimers[d.id] = Timer(const Duration(milliseconds: 250), () => c.didChange(d));
  }

  /// Flushes pending changes before a request so results match the text.
  void flush(EditorDocument d) {
    final Timer? t = _changeTimers.remove(d.id);
    if (t != null && t.isActive) {
      t.cancel();
      clientFor(d)?.didChange(d);
    }
  }

  Future<void> restartAll() async {
    for (final LspClient c in _clients.values) {
      await c.shutdown();
    }
    _clients.clear();
    _missing.clear();
    Toolchain.clearCache();
    for (final EditorDocument d in workspace.openDocuments) {
      _opened(d);
    }
    notifyListeners();
  }

  String statusFor(EditorDocument? d) {
    if (d == null || d.language.lsp == null) return '';
    final String? k = _key(d.language);
    if (_missing.contains(k)) return 'No language server';
    final LspClient? c = _clients[k];
    if (c == null) return '';
    return switch (c.state) {
      LspState.starting => 'Starting ${c.spec.command}…',
      LspState.ready => c.spec.command,
      LspState.failed => '${c.spec.command} failed',
      LspState.stopped => '${c.spec.command} stopped',
    };
  }

  @override
  void dispose() {
    for (final LspClient c in _clients.values) {
      c.shutdown();
    }
    super.dispose();
  }
}
