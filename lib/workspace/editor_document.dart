import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../core/languages.dart';

enum TabKind { text, image, binary, welcome, settings, keybindings, extension, markdownPreview, diff }

/// One tab in an editor group.
class EditorTab {
  // ignore: prefer_initializing_formals
  EditorTab._(this.kind, {this.document, String? path, this.extra}) : _path = path;

  factory EditorTab.text(EditorDocument doc) => EditorTab._(TabKind.text, document: doc);
  factory EditorTab.special(TabKind kind, {String? path, Object? extra}) => EditorTab._(kind, path: path, extra: extra);

  final TabKind kind;
  final EditorDocument? document;
  final String? _path;
  String? get path => document != null ? document!.path : _path;

  /// Extra payload: extension id, diff text, ...
  final Object? extra;

  /// Preview tabs (single click in the explorer) are replaced by the next preview.
  bool preview = false;
  bool pinned = false;

  String get id => switch (kind) {
        TabKind.text => document!.id,
        TabKind.extension => 'ext:$extra',
        TabKind.markdownPreview => 'md:$path',
        TabKind.diff => 'diff:$path',
        _ => '${kind.name}:${path ?? ''}',
      };

  String get title => switch (kind) {
        TabKind.text => document!.title,
        TabKind.welcome => 'Welcome',
        TabKind.settings => 'Settings',
        TabKind.keybindings => 'Keyboard Shortcuts',
        TabKind.extension => 'Extension: ${extra ?? ''}',
        TabKind.markdownPreview => 'Preview ${p.basename(path ?? '')}',
        TabKind.diff => '${p.basename(path ?? '')} (Working Tree)',
        _ => p.basename(path ?? ''),
      };

  bool get isDirty => document?.isDirty ?? false;
}

/// A text document backed by a file (or untitled).
class EditorDocument extends ChangeNotifier {
  EditorDocument._({
    required this.id,
    required this.path,
    required this.language,
    required String text,
    required this.lineBreak,
    required this.untitledIndex,
  }) {
    controller = CodeLineEditingController(
      codeLines: CodeLines.fromText(text),
      options: CodeLineOptions(lineBreak: lineBreak, indentSize: 4),
      spanBuilder: _buildSpan,
    );
    _savedText = controller.text;
    _lastText = _savedText;
    findController = CodeFindController(controller);
    scrollController = CodeScrollController();
    controller.addListener(_onChanged);
  }

  static int _nextId = 0;
  static int _nextUntitled = 1;

  final String id;
  String? path;
  LanguageDef language;
  TextLineBreak lineBreak;
  final int untitledIndex;
  final bool readOnly = false;
  late final CodeLineEditingController controller;
  late final CodeFindController findController;
  late final CodeScrollController scrollController;
  final FocusNode focusNode = FocusNode(debugLabel: 'editor');

  String _savedText = '';
  bool _dirty = false;
  int version = 1;
  DateTime? diskModified;

  /// Optional decorator applied to every rendered line (diagnostics, TODOs).
  TextSpan Function(int index, String line, TextSpan span, TextStyle style)? spanDecorator;

  TextSpan _buildSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) =>
      spanDecorator?.call(index, codeLine.text, textSpan, style) ?? textSpan;

  /// Called (debounced by the workspace) whenever the text changes.
  VoidCallback? onTextChanged;

  bool get isDirty => _dirty;
  bool get isUntitled => path == null;
  String get title => path == null ? 'Untitled-$untitledIndex' : p.basename(path!);
  String get uri => path == null ? 'untitled:$title' : Uri.file(path!, windows: Platform.isWindows).toString();
  String get lineBreakLabel => lineBreak == TextLineBreak.crlf ? 'CRLF' : 'LF';

  static Future<EditorDocument> open(String path) async {
    final File f = File(path);
    final List<int> bytes = await f.readAsBytes();
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }
    if (text.startsWith('﻿')) text = text.substring(1);
    final TextLineBreak lb = text.contains('\r\n') ? TextLineBreak.crlf : TextLineBreak.lf;
    final EditorDocument doc = EditorDocument._(
      id: 'doc${_nextId++}',
      path: path,
      language: languageForPath(path),
      text: text.replaceAll('\r\n', '\n'),
      lineBreak: lb,
      untitledIndex: 0,
    );
    doc.diskModified = await f.lastModified();
    return doc;
  }

  factory EditorDocument.untitled({String text = '', LanguageDef? language}) => EditorDocument._(
        id: 'doc${_nextId++}',
        path: null,
        language: language ?? plainText,
        text: text,
        lineBreak: Platform.isWindows ? TextLineBreak.crlf : TextLineBreak.lf,
        untitledIndex: _nextUntitled++,
      );

  String get text => controller.text;

  void _onChanged() {
    final bool dirty = controller.text != _savedText;
    if (controller.text != _lastText) {
      _lastText = controller.text;
      version++;
      onTextChanged?.call();
    }
    if (dirty != _dirty) {
      _dirty = dirty;
      notifyListeners();
    }
  }

  String _lastText = '';

  /// Writes the document to disk, applying whitespace preferences.
  Future<void> save({String? asPath, bool trimTrailing = true, bool finalNewline = true}) async {
    if (asPath != null) {
      path = asPath;
      language = languageForPath(asPath);
    }
    if (path == null) throw StateError('No path for untitled document');
    String out = controller.text;
    if (trimTrailing) {
      final String trimmed = out.split('\n').map((l) => l.replaceFirst(RegExp(r'[ \t]+$'), '')).join('\n');
      if (trimmed != out) {
        final CodeLineSelection sel = controller.selection;
        controller.text = trimmed;
        _safeSelect(sel);
        out = trimmed;
      }
    }
    if (finalNewline && out.isNotEmpty && !out.endsWith('\n')) out = '$out\n';
    final String disk = lineBreak == TextLineBreak.crlf ? out.replaceAll('\n', '\r\n') : out;
    final File f = File(path!);
    await f.parent.create(recursive: true);
    await f.writeAsString(disk, flush: true);
    diskModified = await f.lastModified();
    _savedText = controller.text;
    _dirty = false;
    notifyListeners();
  }

  void _safeSelect(CodeLineSelection sel) {
    final int maxIndex = controller.codeLines.length - 1;
    final int idx = sel.extentIndex.clamp(0, maxIndex);
    final int off = sel.extentOffset.clamp(0, controller.codeLines[idx].length);
    controller.selection = CodeLineSelection.collapsed(index: idx, offset: off);
  }

  /// Reloads from disk when the file changed externally and has no local edits.
  Future<bool> reloadIfChanged() async {
    if (path == null || _dirty) return false;
    final File f = File(path!);
    if (!await f.exists()) return false;
    final DateTime m = await f.lastModified();
    if (diskModified != null && !m.isAfter(diskModified!)) return false;
    String text = (await f.readAsString()).replaceAll('\r\n', '\n');
    if (text.startsWith('﻿')) text = text.substring(1);
    diskModified = m;
    if (text == controller.text) return false;
    final CodeLineSelection sel = controller.selection;
    controller.text = text;
    _safeSelect(sel);
    _savedText = controller.text;
    _dirty = false;
    notifyListeners();
    return true;
  }

  void markSaved() {
    _savedText = controller.text;
    _dirty = false;
    notifyListeners();
  }

  void revert(String text) {
    controller.text = text;
    markSaved();
  }

  /// Cursor as 1-based (line, column).
  (int, int) get cursor {
    final CodeLineSelection s = controller.selection;
    return (s.extentIndex + 1, s.extentOffset + 1);
  }

  void goTo(int line, [int column = 1]) {
    final int idx = (line - 1).clamp(0, controller.codeLines.length - 1);
    final int off = (column - 1).clamp(0, controller.codeLines[idx].length);
    controller.selection = CodeLineSelection.collapsed(index: idx, offset: off);
    controller.makeCursorCenterIfInvisible();
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    controller.dispose();
    findController.dispose();
    scrollController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
