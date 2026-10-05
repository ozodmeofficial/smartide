import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:window_manager/window_manager.dart';

import '../core/commands.dart';
import '../core/languages.dart';
import '../core/settings.dart';
import '../core/toolchain.dart';
import '../services/assistant_service.dart';
import '../services/extension_service.dart';
import '../services/git_service.dart';
import '../services/live_server.dart';
import '../services/lsp_service.dart';
import '../services/output_service.dart';
import '../services/search_service.dart';
import '../services/terminal_service.dart';
import '../theme/fonts.dart';
import '../theme/ide_theme.dart';
import '../theme/themes.dart';
import '../ui/dialogs.dart';
import '../workspace/editor_document.dart';
import '../workspace/workspace.dart';
import 'quick_pick.dart';

enum SideView { explorer, search, scm, run, extensions }

enum PanelTab { problems, output, terminal }

/// The application controller: owns every service, UI layout state and the
/// command table.
class Ide extends ChangeNotifier {
  /// Notifies listeners after an external mutation of public state.
  void touch() => notifyListeners();

  Ide(this.settings) {
    workspace = Workspace(settings);
    extensions = ExtensionService(settings);
    git = GitService(workspace, output);
    liveServer = LiveServer(workspace, output);
    lsp = LspService(workspace, output, extensions.isLanguageEnabled);
    search = SearchService(workspace);
    assistant = AssistantService(settings);
    workspace.confirmDiscard = _confirmDiscard;
    workspace.askSavePath = _askSavePath;
    settings.addListener(_onSettings);
    extensions.addListener(notifyListeners);
  }

  final Settings settings;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final CommandRegistry commands = CommandRegistry();
  final OutputService output = OutputService();
  final NotificationService notifications = NotificationService();
  final Toolchain toolchain = Toolchain();
  final TerminalService terminals = TerminalService();
  final FontManager fonts = FontManager();
  late final Workspace workspace;
  late final ExtensionService extensions;
  late final GitService git;
  late final LiveServer liveServer;
  late final LspService lsp;
  late final SearchService search;
  late final AssistantService assistant;

  // Layout state
  SideView sideView = SideView.explorer;
  bool sidebarVisible = true;
  bool panelVisible = false;
  bool panelMaximized = false;
  PanelTab panelTab = PanelTab.terminal;
  bool assistantVisible = false;
  bool zenMode = false;
  bool fullScreen = false;
  QuickPickRequest? quickPick;
  final ValueNotifier<int> searchFocusRequest = ValueNotifier<int>(0);

  late IdeTheme theme = themeById(settings.themeId);

  /// Theme shown temporarily while browsing the theme picker.
  IdeTheme? _previewTheme;
  IdeTheme get effectiveTheme => _previewTheme ?? theme;

  List<IdeTheme> get allThemes => [...builtInThemes, ...extensions.extraThemes];

  BuildContext? get context => navigatorKey.currentContext;

  String _lastFont = '';

  Future<void> init({String? openPath}) async {
    await commands.loadKeybindings();
    _registerCommands();
    terminals.defaultProfileId = settings.defaultShell;
    await extensions.loadInstalled();
    theme = themeById(settings.themeId, extensions.extraThemes);
    unawaited(fonts.ensure(settings.editorFont));
    unawaited(fonts.ensure(settings.terminalFont));
    _lastFont = settings.editorFont;
    unawaited(terminals.detectProfiles());
    unawaited(toolchain.scan());
    unawaited(git.init());
    if (openPath != null && await FileSystemEntity.isDirectory(openPath)) {
      await openFolder(openPath);
    } else if (openPath != null && await File(openPath).exists()) {
      await openFolder(p.dirname(openPath));
      await workspace.openFile(openPath);
    } else if (settings.restoreLastWorkspace && settings.lastFolder != null && await Directory(settings.lastFolder!).exists()) {
      await openFolder(settings.lastFolder!);
    }
    if (workspace.activeTab == null) workspace.openSpecial(TabKind.welcome);
  }

  void _onSettings() {
    final IdeTheme next = themeById(settings.themeId, extensions.extraThemes);
    if (next.id != theme.id) theme = next;
    if (settings.editorFont != _lastFont) {
      _lastFont = settings.editorFont;
      fonts.ensure(settings.editorFont);
    }
    fonts.ensure(settings.terminalFont);
    terminals.defaultProfileId = settings.defaultShell;
    for (final EditorDocument d in workspace.openDocuments) {
      d.controller.forceRepaint();
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ layout

  /// Shows a side bar view. [toggle] (used by the activity bar) hides the
  /// side bar when the view is already visible.
  void showView(SideView v, {bool toggle = false}) {
    if (toggle && sideView == v && sidebarVisible) {
      sidebarVisible = false;
    } else {
      sideView = v;
      sidebarVisible = true;
      zenMode = false;
    }
    if (v == SideView.search && sidebarVisible) searchFocusRequest.value++;
    if (v == SideView.extensions && sidebarVisible && extensions.remoteCatalog.isEmpty) extensions.fetchCatalog();
    notifyListeners();
  }

  void toggleSidebar() {
    sidebarVisible = !sidebarVisible;
    notifyListeners();
  }

  void showPanel(PanelTab tab, {bool toggle = false}) {
    if (toggle && panelVisible && panelTab == tab) {
      panelVisible = false;
      focusEditor();
    } else {
      panelTab = tab;
      panelVisible = true;
      if (tab == PanelTab.terminal && terminals.sessions.isEmpty) newTerminal();
    }
    notifyListeners();
  }

  void togglePanel() {
    panelVisible = !panelVisible;
    if (panelVisible && panelTab == PanelTab.terminal && terminals.sessions.isEmpty) newTerminal();
    notifyListeners();
  }

  void toggleAssistant() {
    assistantVisible = !assistantVisible;
    notifyListeners();
  }

  void toggleZen() {
    zenMode = !zenMode;
    notifyListeners();
  }

  void openQuickPick(QuickPickRequest r) {
    quickPick = r;
    notifyListeners();
  }

  void closeQuickPick({bool cancelled = true}) {
    final QuickPickRequest? r = quickPick;
    quickPick = null;
    if (_previewTheme != null) _previewTheme = null;
    if (cancelled) r?.onCancel?.call();
    notifyListeners();
    focusEditor();
  }

  void focusEditor() {
    final EditorDocument? d = workspace.activeDocument;
    if (d != null) {
      Future<void>.delayed(const Duration(milliseconds: 30), () {
        if (d.focusNode.context != null) d.focusNode.requestFocus();
      });
    }
  }

  void newTerminal({ShellProfile? profile}) {
    terminals.cwd = workspace.root;
    terminals.create(profile: profile);
    panelTab = PanelTab.terminal;
    panelVisible = true;
    notifyListeners();
  }

  // ------------------------------------------------------------------ files

  Future<void> openFolder([String? path]) async {
    path ??= await getDirectoryPath(confirmButtonText: 'Open Folder');
    if (path == null) return;
    await workspace.openFolder(path);
    terminals.cwd = workspace.root;
    await git.refresh();
    if (Platform.isWindows) {
      unawaited(windowManager.setTitle('${workspace.folderName} — SmartIDE'));
    }
    sideView = SideView.explorer;
    sidebarVisible = true;
    notifyListeners();
  }

  Future<void> openFileDialog() async {
    final XFile? f = await openFile(initialDirectory: workspace.root);
    if (f != null) await workspace.openFile(f.path);
  }

  Future<String?> _askSavePath(EditorDocument doc) async {
    final String ext = doc.language.extensions.isEmpty ? '.txt' : doc.language.extensions.first;
    final FileSaveLocation? loc = await getSaveLocation(
      initialDirectory: workspace.root,
      suggestedName: doc.isUntitled ? '${doc.title.toLowerCase().replaceAll('-', '')}$ext' : p.basename(doc.path!),
    );
    return loc?.path;
  }

  Future<bool> _confirmDiscard(EditorDocument doc) async {
    final BuildContext? ctx = context;
    if (ctx == null) return true;
    final SaveChoice choice = await showSaveChoice(ctx, doc.title);
    switch (choice) {
      case SaveChoice.save:
        return workspace.saveDocument(doc);
      case SaveChoice.discard:
        return true;
      case SaveChoice.cancel:
        return false;
    }
  }

  /// Returns true when it is safe to quit.
  Future<bool> confirmQuit() async {
    final List<EditorDocument> dirty = workspace.openDocuments.where((d) => d.isDirty).toList();
    if (dirty.isEmpty || context == null) return true;
    final SaveChoice choice = await showSaveChoice(context!, dirty.length == 1 ? dirty.first.title : '${dirty.length} files');
    if (choice == SaveChoice.cancel) return false;
    if (choice == SaveChoice.save) {
      for (final EditorDocument d in dirty) {
        if (!await workspace.saveDocument(d)) return false;
      }
    }
    return true;
  }

  Future<void> save({bool saveAs = false}) async {
    final EditorDocument? d = workspace.activeDocument;
    if (d == null) return;
    if (settings.formatOnSave) await formatDocument(silent: true);
    await workspace.saveDocument(d, saveAs: saveAs);
  }

  // ------------------------------------------------------------------ run

  static const Map<String, String> _toolForLanguage = {
    'python': 'python',
    'c': 'gcc',
    'cpp': 'g++',
    'csharp': 'dotnet',
    'go': 'go',
    'javascript': 'node',
    'typescript': 'node',
    'java': 'java',
    'rust': 'rustc',
    'dart': 'dart',
    'php': 'php',
    'ruby': 'ruby',
  };

  Future<void> runActiveFile() async {
    final EditorDocument? doc = workspace.activeDocument;
    if (doc == null) {
      notifications.info('Open a file to run it.');
      return;
    }
    if (doc.isUntitled || doc.isDirty) {
      if (!await workspace.saveDocument(doc)) return;
    }
    final LanguageDef lang = doc.language;
    if (!extensions.isLanguageEnabled(lang)) {
      notifications.warn('The ${lang.name} extension is disabled.', actions: [
        ToastAction('Enable', () => extensions.setEnabled(lang.extensionId!, true)),
      ]);
      return;
    }
    if (lang.id == 'html') {
      await toggleLiveServer(openPath: doc.path);
      return;
    }
    if (lang.id == 'markdown') {
      workspace.openSpecial(TabKind.markdownPreview, path: doc.path);
      return;
    }
    final String? toolId = _toolForLanguage[lang.id];
    final ToolInfo? tool = toolId == null ? null : toolchain[toolId];
    if (tool != null && tool.checked && !tool.available) {
      notifications.error(
        '${tool.name} was not found on this computer.',
        detail: 'Install it with:  ${tool.installHint}',
        actions: [
          ToastAction('Install in terminal', () {
            showPanel(PanelTab.terminal);
            terminals.sendToActive(tool.installHint.split('  ').first);
          }),
          ToastAction('Download page', () => LiveServer.openInBrowser(tool.url)),
        ],
      );
      return;
    }
    final String? cmd = lang.run?.call(RunContext(file: doc.path!, workspace: workspace.root, tools: toolchain.resolvedMap));
    if (cmd == null) {
      notifications.info('No runner is configured for ${lang.name} files.');
      return;
    }
    terminals.cwd = workspace.root;
    terminals.runTask('▶ ${doc.title}', cmd, workingDirectory: p.dirname(doc.path!));
    panelTab = PanelTab.terminal;
    panelVisible = true;
    notifyListeners();
  }

  void stopRun() {
    final TerminalSession? s = terminals.sessions.where((s) => s.isTask && !s.exited).lastOrNull;
    s?.kill();
  }

  Future<void> runBuildTask() async {
    final String? root = workspace.root;
    if (root == null) return runActiveFile();
    bool has(String f) => File(p.join(root, f)).existsSync();
    String? cmd;
    if (has('package.json')) {
      cmd = 'npm run build';
    } else if (has('Cargo.toml')) {
      cmd = 'cargo build';
    } else if (has('go.mod')) {
      cmd = 'go build ./...';
    } else if (has('pubspec.yaml')) {
      cmd = 'dart pub get && dart analyze';
    } else if (has('CMakeLists.txt')) {
      cmd = 'cmake -S . -B build && cmake --build build';
    } else if (has('Makefile')) {
      cmd = 'make';
    } else if (Directory(root).listSync().any((e) => e.path.endsWith('.csproj') || e.path.endsWith('.sln'))) {
      cmd = 'dotnet build';
    } else if (has('pom.xml')) {
      cmd = 'mvn -q package';
    } else if (has('build.gradle') || has('build.gradle.kts')) {
      cmd = Platform.isWindows ? 'gradlew.bat build' : './gradlew build';
    }
    if (cmd == null) return runActiveFile();
    terminals.runTask('⚒ Build', cmd, workingDirectory: root);
    panelTab = PanelTab.terminal;
    panelVisible = true;
    notifyListeners();
  }

  Future<void> toggleLiveServer({String? openPath}) async {
    if (!extensions.isEnabled('smartide.liveserver')) {
      notifications.warn('Live Server extension is disabled.');
      return;
    }
    if (liveServer.running && openPath == null) {
      await liveServer.stop();
      notifications.info('Live Server stopped.');
      return;
    }
    if (liveServer.running && openPath != null) {
      final String rel = p.relative(openPath, from: workspace.root ?? p.dirname(openPath)).replaceAll('\\', '/');
      LiveServer.openInBrowser('${liveServer.url}$rel');
      return;
    }
    final String? root = workspace.root ?? (openPath == null ? null : p.dirname(openPath));
    if (root == null) {
      notifications.info('Open a folder or an HTML file first.');
      return;
    }
    final bool ok = await liveServer.start(root: root, preferredPort: settings.liveServerPort, openPath: openPath);
    if (ok) {
      notifications.success('Live Server started on port ${liveServer.port}', detail: liveServer.url);
    } else {
      notifications.error('Could not start Live Server (ports busy).');
    }
  }

  // ------------------------------------------------------------------ editor actions

  CodeLineEditingController? get _ctl => workspace.activeDocument?.controller;

  void selectNextOccurrence() {
    final CodeLineEditingController? c = _ctl;
    if (c == null) return;
    final CodeLineSelection sel = c.selection;
    if (sel.isCollapsed) {
      // Select the word under the cursor.
      final String line = c.codeLines[sel.extentIndex].text;
      int s = sel.extentOffset, e = sel.extentOffset;
      bool isWord(int i) => i >= 0 && i < line.length && RegExp(r'[A-Za-z0-9_$]').hasMatch(line[i]);
      while (isWord(s - 1)) {
        s--;
      }
      while (isWord(e)) {
        e++;
      }
      if (s == e) return;
      c.selection = CodeLineSelection(baseIndex: sel.extentIndex, baseOffset: s, extentIndex: sel.extentIndex, extentOffset: e);
      return;
    }
    final String needle = c.selectedText;
    if (needle.isEmpty || needle.contains('\n')) return;
    final int lines = c.codeLines.length;
    final int startLine = sel.end.index;
    for (int k = 0; k <= lines; k++) {
      final int li = (startLine + k) % lines;
      final String text = c.codeLines[li].text;
      final int from = k == 0 ? sel.end.offset : 0;
      final int idx = text.indexOf(needle, from);
      if (idx >= 0) {
        c.selection = CodeLineSelection(baseIndex: li, baseOffset: idx, extentIndex: li, extentOffset: idx + needle.length);
        c.makeCursorCenterIfInvisible();
        return;
      }
    }
  }

  void duplicateLines({required bool down}) {
    final CodeLineEditingController? c = _ctl;
    if (c == null) return;
    final CodeLineSelection sel = c.selection;
    final int a = sel.start.index, b = sel.end.index;
    final List<String> block = [for (int i = a; i <= b; i++) c.codeLines[i].text];
    c.runRevocableOp(() {
      c.selection = CodeLineSelection.collapsed(index: b, offset: c.codeLines[b].length);
      c.replaceSelection('\n${block.join('\n')}');
      if (!down) {
        c.selection = CodeLineSelection(baseIndex: a, baseOffset: sel.baseOffset, extentIndex: b, extentOffset: sel.extentOffset);
      }
    });
  }

  void insertLine({required bool after}) {
    final CodeLineEditingController? c = _ctl;
    if (c == null) return;
    final int i = c.selection.extentIndex;
    final String line = c.codeLines[i].text;
    final String indent = RegExp(r'^\s*').firstMatch(line)!.group(0)!;
    if (after) {
      c.selection = CodeLineSelection.collapsed(index: i, offset: line.length);
      c.replaceSelection('\n$indent');
    } else {
      c.selection = CodeLineSelection.collapsed(index: i, offset: 0);
      c.replaceSelection('$indent\n');
      c.selection = CodeLineSelection.collapsed(index: i, offset: indent.length);
    }
  }

  void jumpToBracket() {
    final CodeLineEditingController? c = _ctl;
    if (c == null) return;
    const String open = '([{', close = ')]}';
    final int li = c.selection.extentIndex;
    final int off = c.selection.extentOffset;
    final String line = c.codeLines[li].text;
    int at = -1;
    if (off < line.length && (open + close).contains(line[off])) {
      at = off;
    } else if (off > 0 && (open + close).contains(line[off - 1])) {
      at = off - 1;
    }
    if (at < 0) return;
    final String ch = line[at];
    final bool forward = open.contains(ch);
    final String match = forward ? close[open.indexOf(ch)] : open[close.indexOf(ch)];
    int depth = 0;
    int l = li, o = at;
    while (l >= 0 && l < c.codeLines.length) {
      final String t = c.codeLines[l].text;
      while (o >= 0 && o < t.length) {
        if (t[o] == ch) depth++;
        if (t[o] == match) depth--;
        if (depth == 0) {
          c.selection = CodeLineSelection.collapsed(index: l, offset: forward ? o + 1 : o);
          c.makeCursorCenterIfInvisible();
          return;
        }
        o += forward ? 1 : -1;
      }
      l += forward ? 1 : -1;
      if (l >= 0 && l < c.codeLines.length) o = forward ? 0 : c.codeLines[l].length - 1;
    }
  }

  void indentLines(bool indent) {
    final CodeLineEditingController? c = _ctl;
    if (c == null) return;
    indent ? c.applyIndent() : c.applyOutdent();
  }

  Future<void> formatDocument({bool silent = false}) async {
    final EditorDocument? d = workspace.activeDocument;
    if (d == null) return;
    final LspClient? client = lsp.clientFor(d);
    if (client == null || client.capabilities['documentFormattingProvider'] == null) {
      if (!silent) notifications.info('No formatter available for ${d.language.name}.', detail: 'Install its language server to enable formatting.');
      return;
    }
    lsp.flush(d);
    final List<LspTextEdit> edits = await client.format(d, settings.tabSize, settings.insertSpaces);
    if (edits.isEmpty) return;
    final List<String> lines = d.text.split('\n');
    int offsetOf(int line, int col) {
      int o = 0;
      for (int i = 0; i < line && i < lines.length; i++) {
        o += lines[i].length + 1;
      }
      return o + col;
    }

    String text = d.text;
    final List<LspTextEdit> sorted = [...edits]..sort((a, b) => offsetOf(b.startLine, b.startCol).compareTo(offsetOf(a.startLine, a.startCol)));
    for (final LspTextEdit e in sorted) {
      final int s = offsetOf(e.startLine, e.startCol).clamp(0, text.length);
      final int en = offsetOf(e.endLine, e.endCol).clamp(s, text.length);
      text = text.replaceRange(s, en, e.newText.replaceAll('\r\n', '\n'));
    }
    final (int line, int col) = d.cursor;
    d.controller.runRevocableOp(() => d.controller.text = text);
    d.goTo(line, col);
  }

  Future<void> goToDefinition() async {
    final EditorDocument? d = workspace.activeDocument;
    if (d == null) return;
    final LspClient? client = lsp.clientFor(d);
    if (client == null) {
      notifications.info('Go to Definition needs a language server for ${d.language.name}.');
      return;
    }
    lsp.flush(d);
    final CodeLineSelection s = d.controller.selection;
    final LspLocation? loc = await client.definition(d, s.extentIndex, s.extentOffset);
    if (loc == null) {
      notifications.info('No definition found.');
      return;
    }
    await workspace.openFile(loc.path, line: loc.line, column: loc.column);
  }

  Future<void> showHover() async {
    final EditorDocument? d = workspace.activeDocument;
    final LspClient? client = d == null ? null : lsp.clientFor(d);
    if (d == null || client == null) return;
    final CodeLineSelection s = d.controller.selection;
    final String? text = await client.hover(d, s.extentIndex, s.extentOffset);
    if (text != null && text.trim().isNotEmpty) notifications.info(text.length > 600 ? '${text.substring(0, 600)}…' : text);
  }

  Future<void> triggerSuggest() async {
    final EditorDocument? d = workspace.activeDocument;
    if (d == null) return;
    final CodeLineSelection s = d.controller.selection;
    final String line = d.controller.codeLines[s.extentIndex].text;
    int start = s.extentOffset;
    while (start > 0 && RegExp(r'[A-Za-z0-9_$]').hasMatch(line[start - 1])) {
      start--;
    }
    final String prefix = line.substring(start, s.extentOffset);
    final List<QuickPickItem> items = [];
    final LspClient? client = lsp.clientFor(d);
    if (client != null) {
      lsp.flush(d);
      for (final LspCompletion c in await client.completion(d, s.extentIndex, s.extentOffset)) {
        items.add(QuickPickItem(label: c.label, description: c.detail, icon: Icons.data_object_rounded, value: c.insertText ?? c.label));
      }
    }
    for (final Snippet sn in [...d.language.snippets, ...?extensions.extraSnippets[d.language.id]]) {
      items.add(QuickPickItem(label: sn.prefix, description: sn.label, icon: Icons.content_paste_go_rounded, value: sn));
    }
    openQuickPick(QuickPickRequest(
      placeholder: 'Suggestions',
      items: items,
      initialValue: prefix,
      onAccept: (item, _) {
        d.controller.selection = CodeLineSelection(baseIndex: s.extentIndex, baseOffset: start, extentIndex: s.extentIndex, extentOffset: s.extentOffset);
        final Object? v = item.value;
        if (v is Snippet) {
          insertSnippet(d, v.body);
        } else {
          insertSnippet(d, '$v');
        }
      },
    ));
  }

  /// Inserts a snippet body, expanding `${n:placeholder}` tab stops and
  /// placing the cursor at the first one.
  void insertSnippet(EditorDocument d, String body) {
    final CodeLineEditingController c = d.controller;
    final String indent = RegExp(r'^\s*').firstMatch(c.codeLines[c.selection.start.index].text)!.group(0)!;
    final String unit = settings.insertSpaces ? ' ' * settings.tabSize : '\t';
    String text = body.replaceAll('\t', unit).replaceAll('\n', '\n$indent');
    int? cursor;
    int? selLen;
    final RegExp stop = RegExp(r'\$\{(\d+):([^}]*)\}|\$(\d+)');
    final StringBuffer out = StringBuffer();
    int last = 0;
    int bestIndex = 1 << 30;
    for (final RegExpMatch m in stop.allMatches(text)) {
      out.write(text.substring(last, m.start));
      final int n = int.parse(m.group(1) ?? m.group(3)!);
      final String ph = m.group(2) ?? '';
      final int rank = n == 0 ? 1 << 29 : n;
      if (rank < bestIndex) {
        bestIndex = rank;
        cursor = out.length;
        selLen = ph.length;
      }
      out.write(ph);
      last = m.end;
    }
    out.write(text.substring(last));
    text = out.toString();
    final CodeLinePosition startPos = c.selection.start;
    c.replaceSelection(text);
    if (cursor != null) {
      final String before = text.substring(0, cursor);
      final int nl = '\n'.allMatches(before).length;
      final int col = nl == 0 ? startPos.offset + before.length : before.length - before.lastIndexOf('\n') - 1;
      final int li = startPos.index + nl;
      c.selection = CodeLineSelection(baseIndex: li, baseOffset: col, extentIndex: li, extentOffset: col + (selLen ?? 0));
    }
  }

  void toggleWordWrap() => settings.update((s) => s.wordWrap = !s.wordWrap);

  void zoom(double delta) => settings.update((s) => s.uiScale = delta == 0 ? 1.0 : (s.uiScale + delta).clamp(0.7, 1.8));

  void editorFontZoom(double delta) => settings.update((s) => s.editorFontSize = (s.editorFontSize + delta).clamp(8, 40));

  void nextProblem(int dir) {
    final EditorDocument? d = workspace.activeDocument;
    if (d?.path == null) return;
    final List<Diagnostic> list = [...?workspace.diagnostics[d!.path]]..sort((a, b) => a.line.compareTo(b.line));
    if (list.isEmpty) return;
    final int cur = d.controller.selection.extentIndex;
    final Diagnostic target = dir > 0
        ? list.firstWhere((x) => x.line > cur, orElse: () => list.first)
        : list.lastWhere((x) => x.line < cur, orElse: () => list.last);
    d.goTo(target.line + 1, target.column + 1);
    notifications.show(target.message, kind: target.severity == DiagnosticSeverity.error ? ToastKind.error : ToastKind.warning, duration: const Duration(seconds: 4));
  }

  // ------------------------------------------------------------------ pickers

  void showCommandPalette([String initial = '']) {
    final List<Command> cmds = commands.all.where((c) => c.isEnabled).toList()..sort((a, b) => a.label.compareTo(b.label));
    openQuickPick(QuickPickRequest(
      placeholder: 'Type a command',
      initialValue: initial,
      items: [
        for (final Command c in cmds) QuickPickItem(label: c.label, keybinding: commands.shortcutFor(c.id), value: c.id),
      ],
      onAccept: (item, _) => Future<void>.delayed(const Duration(milliseconds: 10), () => commands.execute(item.value! as String)),
    ));
  }

  List<String>? _fileCache;
  DateTime? _fileCacheTime;

  Future<List<String>> _files() async {
    if (_fileCache == null || DateTime.now().difference(_fileCacheTime!) > const Duration(seconds: 20)) {
      _fileCache = await workspace.listAllFiles();
      _fileCacheTime = DateTime.now();
    }
    return _fileCache!;
  }

  void showQuickOpen() {
    openQuickPick(QuickPickRequest(
      placeholder: 'Search files by name (append : to go to line, > for commands)',
      loader: (q) async {
        if (q.startsWith('>')) return const [];
        if (q.startsWith(':')) {
          return [QuickPickItem(label: 'Go to line ${q.substring(1)}', icon: Icons.format_list_numbered_rounded, value: q)];
        }
        final List<String> files = await _files();
        final List<(int, String)> scored = [];
        String query = q.trim();
        if (query.isEmpty) {
          final List<String> recent = [for (final EditorDocument d in workspace.openDocuments) if (d.path != null) d.path!];
          return [
            for (final String f in recent.take(12))
              QuickPickItem(label: p.basename(f), description: workspace.relative(p.dirname(f)), badge: languageForPath(f).badge, iconColor: languageForPath(f).color, value: f, separatorAbove: f == recent.first ? 'recently opened' : null),
            for (final String f in files.where((f) => !recent.contains(f)).take(40))
              QuickPickItem(label: p.basename(f), description: workspace.relative(p.dirname(f)), badge: languageForPath(f).badge, iconColor: languageForPath(f).color, value: f),
          ];
        }
        query = query.replaceAll('\\', '/');
        for (final String f in files) {
          final String rel = workspace.relative(f).replaceAll('\\', '/');
          final int? nameScore = fuzzyScore(p.basename(f), query);
          final int? relScore = fuzzyScore(rel, query);
          final int? s = nameScore != null ? nameScore + 200 : relScore;
          if (s != null) scored.add((s, f));
        }
        scored.sort((a, b) => b.$1.compareTo(a.$1));
        return [
          for (final (int, String) e in scored.take(60))
            QuickPickItem(label: p.basename(e.$2), description: workspace.relative(p.dirname(e.$2)), badge: languageForPath(e.$2).badge, iconColor: languageForPath(e.$2).color, value: e.$2),
        ];
      },
      onAccept: (item, q) {
        if (q.startsWith('>')) return;
        final String v = item.value! as String;
        if (v.startsWith(':')) {
          final List<String> parts = v.substring(1).split(':');
          workspace.activeDocument?.goTo(int.tryParse(parts[0]) ?? 1, parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1);
          return;
        }
        workspace.openFile(v);
      },
    ));
  }

  void showGotoLine() {
    final EditorDocument? d = workspace.activeDocument;
    if (d == null) return;
    final (int line, int col) = d.cursor;
    openQuickPick(QuickPickRequest(
      placeholder: 'Current line: $line, Character: $col. Type a line number between 1 and ${d.controller.lineCount} to navigate to.',
      inputOnly: true,
      onInput: (t) {
        final List<String> parts = t.replaceFirst(':', '').split(RegExp(r'[:,]'));
        final int? l = int.tryParse(parts.first.trim());
        if (l != null) d.goTo(l, parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 1 : 1);
      },
    ));
  }

  void showThemePicker() {
    final IdeTheme original = theme;
    openQuickPick(QuickPickRequest(
      placeholder: 'Select Color Theme (Up/Down keys to preview)',
      items: [
        for (final IdeTheme t in allThemes)
          QuickPickItem(
            label: t.name,
            description: t.id == original.id ? 'current' : (t.isDark ? 'dark' : 'light'),
            icon: Icons.circle,
            iconColor: t.accent,
            value: t.id,
            separatorAbove: t == allThemes.first ? 'SmartIDE themes' : (t.id == 'dark-modern' ? 'more themes' : null),
          ),
      ],
      onActive: (item) {
        _previewTheme = themeById(item.value! as String, extensions.extraThemes);
        notifyListeners();
      },
      onAccept: (item, _) {
        _previewTheme = null;
        settings.update((s) => s.themeId = item.value! as String);
      },
      onCancel: () {
        _previewTheme = null;
        notifyListeners();
      },
    ));
  }

  void showFontPicker() {
    openQuickPick(QuickPickRequest(
      placeholder: 'Select Editor Font',
      items: [
        for (final CodeFont f in codeFonts)
          QuickPickItem(
            label: f.family,
            description: f.note,
            detail: f.source == FontSource.download && !fonts.isCached(f) ? 'downloads on first use' : null,
            icon: Icons.text_fields_rounded,
            value: f.family,
          ),
      ],
      onAccept: (item, _) => settings.update((s) => s.editorFont = item.value! as String),
    ));
  }

  void showShellPicker() {
    openQuickPick(QuickPickRequest(
      placeholder: 'Select a terminal profile',
      items: [
        for (final ShellProfile pr in terminals.profiles)
          QuickPickItem(label: pr.name, description: pr.executable, icon: Icons.terminal_rounded, value: pr.id),
      ],
      onAccept: (item, _) => newTerminal(profile: terminals.profiles.firstWhere((x) => x.id == item.value)),
    ));
  }

  void showDefaultShellPicker() {
    openQuickPick(QuickPickRequest(
      placeholder: 'Select the default terminal profile',
      items: [
        for (final ShellProfile pr in terminals.profiles)
          QuickPickItem(label: pr.name, description: pr.id == terminals.defaultProfile.id ? 'default' : pr.executable, icon: Icons.terminal_rounded, value: pr.id),
      ],
      onAccept: (item, _) => settings.update((s) => s.defaultShell = item.value! as String),
    ));
  }

  void showLanguagePicker() {
    final EditorDocument? d = workspace.activeDocument;
    if (d == null) return;
    openQuickPick(QuickPickRequest(
      placeholder: 'Select Language Mode',
      items: [
        for (final LanguageDef l in languages)
          QuickPickItem(label: l.name, description: l.extensions.take(4).join(' '), badge: l.badge, iconColor: l.color, value: l.id),
      ],
      onAccept: (item, _) {
        d.language = languageById(item.value! as String) ?? plainText;
        d.controller.forceRepaint();
        workspace.touch();
      },
    ));
  }

  Future<void> showBranchPicker() async {
    if (!git.isRepo) return;
    await git.loadBranches();
    openQuickPick(QuickPickRequest(
      placeholder: 'Select a branch to checkout, or type a new branch name',
      loader: (q) async => [
        if (q.trim().isNotEmpty && !git.branches.contains(q.trim()))
          QuickPickItem(label: 'Create new branch "${q.trim()}"', icon: Icons.add_rounded, value: '+${q.trim()}'),
        for (final String b in git.branches.where((b) => fuzzyScore(b, q) != null))
          QuickPickItem(label: b, description: b == git.branch ? 'current' : (b.contains('/') ? 'remote' : ''), icon: Icons.call_split_rounded, value: b),
      ],
      onAccept: (item, _) async {
        final String v = item.value! as String;
        final bool ok = v.startsWith('+') ? await git.createBranch(v.substring(1)) : await git.checkout(v.replaceFirst(RegExp(r'^origin/'), ''));
        if (!ok) notifications.error('Git: ${git.lastError ?? 'checkout failed'}');
      },
    ));
  }

  Future<void> newFileQuick() async {
    final BuildContext? ctx = context;
    if (ctx == null) return;
    if (!workspace.hasFolder) {
      workspace.newUntitled();
      return;
    }
    final String? name = await showInputDialog(ctx, title: 'New File', hint: 'e.g. main.py or src/app.js');
    if (name == null || name.trim().isEmpty) return;
    await workspace.createFile(workspace.root!, name.trim());
  }

  // ------------------------------------------------------------------ commands

  void _registerCommands() {
    final List<Command> list = [
      Command(id: 'workbench.action.showCommands', title: 'Show All Commands', run: showCommandPalette, hidden: true),
      Command(id: 'workbench.action.quickOpen', title: 'Go to File…', category: 'File', run: showQuickOpen),
      Command(id: 'workbench.action.gotoLine', title: 'Go to Line…', category: 'Go', run: showGotoLine),
      Command(id: 'workbench.action.toggleSidebarVisibility', title: 'Toggle Primary Side Bar', category: 'View', run: toggleSidebar),
      Command(id: 'workbench.action.togglePanel', title: 'Toggle Panel', category: 'View', run: togglePanel),
      Command(id: 'workbench.action.terminal.toggleTerminal', title: 'Toggle Terminal', category: 'View', run: () => showPanel(PanelTab.terminal, toggle: true)),
      Command(id: 'workbench.action.terminal.new', title: 'Create New Terminal', category: 'Terminal', run: newTerminal),
      Command(id: 'workbench.action.terminal.newWithProfile', title: 'Create New Terminal (With Profile)…', category: 'Terminal', run: showShellPicker),
      Command(id: 'workbench.action.terminal.selectDefaultShell', title: 'Select Default Profile', category: 'Terminal', run: showDefaultShellPicker),
      Command(id: 'workbench.action.terminal.clear', title: 'Clear', category: 'Terminal', run: terminals.clearActive),
      Command(id: 'workbench.action.terminal.kill', title: 'Kill the Active Terminal Instance', category: 'Terminal', run: () {
        final TerminalSession? s = terminals.active;
        if (s != null) terminals.close(s);
      }),
      Command(id: 'workbench.view.explorer', title: 'Show Explorer', category: 'View', run: () => showView(SideView.explorer)),
      Command(id: 'workbench.view.search', title: 'Show Search', category: 'View', run: () {
        sideView = SideView.search;
        sidebarVisible = true;
        searchFocusRequest.value++;
        notifyListeners();
      }),
      Command(id: 'workbench.view.scm', title: 'Show Source Control', category: 'View', run: () => showView(SideView.scm)),
      Command(id: 'workbench.view.debug', title: 'Show Run', category: 'View', run: () => showView(SideView.run)),
      Command(id: 'workbench.view.extensions', title: 'Show Extensions', category: 'View', run: () => showView(SideView.extensions)),
      Command(id: 'workbench.actions.view.problems', title: 'Show Problems', category: 'View', run: () => showPanel(PanelTab.problems, toggle: true)),
      Command(id: 'workbench.action.output.toggleOutput', title: 'Toggle Output', category: 'View', run: () => showPanel(PanelTab.output, toggle: true)),
      Command(id: 'workbench.action.openSettings', title: 'Open Settings', category: 'Preferences', run: () => workspace.openSpecial(TabKind.settings)),
      Command(id: 'workbench.action.openGlobalKeybindings', title: 'Open Keyboard Shortcuts', category: 'Preferences', run: () => workspace.openSpecial(TabKind.keybindings)),
      Command(id: 'workbench.action.selectTheme', title: 'Color Theme', category: 'Preferences', run: showThemePicker),
      Command(id: 'workbench.action.selectFont', title: 'Editor Font', category: 'Preferences', run: showFontPicker),
      Command(id: 'workbench.action.toggleLightDark', title: 'Toggle Light / Dark Theme', category: 'Preferences', run: () {
        settings.update((s) => s.themeId = theme.isDark ? 'claude-light' : 'claude-dark');
      }),
      Command(id: 'workbench.action.zoomIn', title: 'Zoom In', category: 'View', run: () => zoom(0.1)),
      Command(id: 'workbench.action.zoomOut', title: 'Zoom Out', category: 'View', run: () => zoom(-0.1)),
      Command(id: 'workbench.action.zoomReset', title: 'Reset Zoom', category: 'View', run: () => zoom(0)),
      Command(id: 'editor.action.fontZoomIn', title: 'Increase Editor Font Size', category: 'View', run: () => editorFontZoom(1)),
      Command(id: 'editor.action.fontZoomOut', title: 'Decrease Editor Font Size', category: 'View', run: () => editorFontZoom(-1)),
      Command(id: 'workbench.action.toggleFullScreen', title: 'Toggle Full Screen', category: 'View', run: () async {
        fullScreen = !fullScreen;
        await windowManager.setFullScreen(fullScreen);
        notifyListeners();
      }),
      Command(id: 'workbench.action.toggleZenMode', title: 'Toggle Zen Mode', category: 'View', run: toggleZen),
      Command(id: 'workbench.action.toggleAssistant', title: 'Toggle SmartIDE Assistant', category: 'View', run: toggleAssistant, enabled: () => extensions.isEnabled('smartide.assistant')),
      Command(id: 'workbench.action.files.newUntitledFile', title: 'New Text File', category: 'File', run: () => workspace.newUntitled()),
      Command(id: 'workbench.action.files.newFile', title: 'New File…', category: 'File', run: newFileQuick),
      Command(id: 'workbench.action.files.openFile', title: 'Open File…', category: 'File', run: openFileDialog),
      Command(id: 'workbench.action.files.openFolder', title: 'Open Folder…', category: 'File', run: openFolder),
      Command(id: 'workbench.action.closeFolder', title: 'Close Folder', category: 'File', run: () {
        workspace.closeFolder();
        notifyListeners();
      }, enabled: () => workspace.hasFolder),
      Command(id: 'workbench.action.files.save', title: 'Save', category: 'File', run: save),
      Command(id: 'workbench.action.files.saveAs', title: 'Save As…', category: 'File', run: () => save(saveAs: true)),
      Command(id: 'workbench.action.files.saveAll', title: 'Save All', category: 'File', run: workspace.saveAll),
      Command(id: 'workbench.action.files.revert', title: 'Revert File', category: 'File', run: () async {
        final EditorDocument? d = workspace.activeDocument;
        if (d?.path != null) d!.revert((await File(d.path!).readAsString()).replaceAll('\r\n', '\n'));
      }),
      Command(id: 'workbench.action.closeActiveEditor', title: 'Close Editor', category: 'View', run: workspace.closeActive),
      Command(id: 'workbench.action.closeAllEditors', title: 'Close All Editors', category: 'View', run: workspace.closeAll),
      Command(id: 'workbench.action.closeOtherEditors', title: 'Close Other Editors', category: 'View', run: () {
        final EditorTab? t = workspace.activeTab;
        if (t != null) workspace.closeOthers(t);
      }),
      Command(id: 'workbench.action.reopenClosedEditor', title: 'Reopen Closed Editor', category: 'View', run: workspace.reopenClosed),
      Command(id: 'workbench.action.nextEditor', title: 'Open Next Editor', category: 'View', run: () => workspace.cycleTab(1)),
      Command(id: 'workbench.action.previousEditor', title: 'Open Previous Editor', category: 'View', run: () => workspace.cycleTab(-1)),
      Command(id: 'workbench.action.splitEditor', title: 'Split Editor', category: 'View', run: workspace.splitEditor),
      Command(id: 'workbench.action.newWindow', title: 'New Window', category: 'File', run: () {
        Process.start(Platform.resolvedExecutable, [], mode: ProcessStartMode.detached);
      }),
      Command(id: 'workbench.action.quit', title: 'Exit', category: 'File', run: () => windowManager.close()),
      Command(id: 'editor.action.addSelectionToNextFindMatch', title: 'Select Next Occurrence', category: 'Selection', run: selectNextOccurrence),
      Command(id: 'editor.action.copyLinesDownAction', title: 'Copy Line Down', category: 'Edit', run: () => duplicateLines(down: true)),
      Command(id: 'editor.action.copyLinesUpAction', title: 'Copy Line Up', category: 'Edit', run: () => duplicateLines(down: false)),
      Command(id: 'editor.action.insertLineAfter', title: 'Insert Line Below', category: 'Edit', run: () => insertLine(after: true)),
      Command(id: 'editor.action.insertLineBefore', title: 'Insert Line Above', category: 'Edit', run: () => insertLine(after: false)),
      Command(id: 'editor.action.jumpToBracket', title: 'Go to Bracket', category: 'Go', run: jumpToBracket),
      Command(id: 'editor.action.indentLines', title: 'Indent Line', category: 'Edit', run: () => indentLines(true)),
      Command(id: 'editor.action.outdentLines', title: 'Outdent Line', category: 'Edit', run: () => indentLines(false)),
      Command(id: 'editor.action.formatDocument', title: 'Format Document', category: 'Edit', run: formatDocument),
      Command(id: 'editor.action.triggerSuggest', title: 'Trigger Suggest', category: 'Edit', run: triggerSuggest),
      Command(id: 'editor.action.revealDefinition', title: 'Go to Definition', category: 'Go', run: goToDefinition),
      Command(id: 'editor.action.showHover', title: 'Show Hover', category: 'Edit', run: showHover),
      Command(id: 'editor.action.wordWrap', title: 'Toggle Word Wrap', category: 'View', run: toggleWordWrap),
      Command(id: 'editor.action.marker.next', title: 'Go to Next Problem', category: 'Go', run: () => nextProblem(1)),
      Command(id: 'editor.action.marker.prev', title: 'Go to Previous Problem', category: 'Go', run: () => nextProblem(-1)),
      Command(id: 'editor.action.changeLanguage', title: 'Change Language Mode', category: 'Edit', run: showLanguagePicker),
      Command(id: 'markdown.showPreview', title: 'Open Preview to the Side', category: 'Markdown', run: () {
        final EditorDocument? d = workspace.activeDocument;
        if (d?.path != null) workspace.openSpecial(TabKind.markdownPreview, path: d!.path);
      }, enabled: () => workspace.activeDocument?.language.id == 'markdown'),
      Command(id: 'workbench.action.debug.start', title: 'Run Current File', category: 'Run', run: runActiveFile),
      Command(id: 'workbench.action.debug.run', title: 'Run Without Debugging', category: 'Run', run: runActiveFile),
      Command(id: 'workbench.action.debug.stop', title: 'Stop', category: 'Run', run: stopRun),
      Command(id: 'workbench.action.tasks.build', title: 'Run Build Task', category: 'Tasks', run: runBuildTask),
      Command(id: 'liveServer.toggle', title: 'Open with Live Server / Stop', category: 'Live Server', run: () => toggleLiveServer()),
      Command(id: 'git.refresh', title: 'Refresh', category: 'Git', run: git.refresh),
      Command(id: 'git.init', title: 'Initialize Repository', category: 'Git', run: git.initRepo, enabled: () => workspace.hasFolder && !git.isRepo),
      Command(id: 'git.checkout', title: 'Checkout to…', category: 'Git', run: showBranchPicker, enabled: () => git.isRepo),
      Command(id: 'git.pull', title: 'Pull', category: 'Git', run: () => _gitOp(git.pull, 'Pulled')),
      Command(id: 'git.push', title: 'Push', category: 'Git', run: () => _gitOp(git.push, 'Pushed')),
      Command(id: 'git.fetch', title: 'Fetch', category: 'Git', run: () => _gitOp(git.fetch, 'Fetched')),
      Command(id: 'git.sync', title: 'Sync', category: 'Git', run: () => _gitOp(git.sync, 'Synced')),
      Command(id: 'git.stash', title: 'Stash', category: 'Git', run: () => _gitOp(git.stash, 'Stashed')),
      Command(id: 'git.stashPop', title: 'Pop Stash', category: 'Git', run: () => _gitOp(git.stashPop, 'Stash applied')),
      Command(id: 'smartide.detectTools', title: 'Re-scan Installed Tools', category: 'SmartIDE', run: () {
        Toolchain.clearCache();
        toolchain.scan();
        showView(SideView.run);
      }),
      Command(id: 'smartide.restartLanguageServers', title: 'Restart Language Servers', category: 'SmartIDE', run: lsp.restartAll),
      Command(id: 'smartide.openDataFolder', title: 'Open Settings Folder', category: 'SmartIDE', run: () => openFolder(p.dirname(settingsPathHint))),
      Command(id: 'workbench.action.openWelcome', title: 'Welcome', category: 'Help', run: () => workspace.openSpecial(TabKind.welcome)),
      Command(id: 'revealFileInOS', title: 'Reveal in File Explorer', category: 'File', run: () {
        final String? path = workspace.activeTab?.path;
        if (path != null) revealInOs(path);
      }),
      Command(id: 'copyFilePath', title: 'Copy Path of Active File', category: 'File', run: () {
        final String? path = workspace.activeTab?.path;
        if (path != null) Clipboard.setData(ClipboardData(text: path));
      }),
    ];
    commands.registerAll(list);
  }

  String get settingsPathHint => p.join(Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? '.', 'SmartIDE', 'settings.json');

  Future<void> _gitOp(Future<bool> Function() op, String done) async {
    final int id = notifications.show('Git: working…', progress: true);
    final bool ok = await op();
    notifications.dismiss(id);
    if (ok) {
      notifications.success('Git: $done');
    } else {
      notifications.error('Git failed', detail: git.lastError, actions: [ToastAction('Show Output', () {
        output.select('Git');
        showPanel(PanelTab.output);
      })]);
    }
  }

  static void revealInOs(String path) {
    if (Platform.isWindows) {
      Process.run('explorer', ['/select,', path]);
    } else if (Platform.isMacOS) {
      Process.run('open', ['-R', path]);
    } else {
      Process.run('xdg-open', [p.dirname(path)]);
    }
  }

  /// Workbench commands that keep working while the terminal has focus
  /// (VS Code's "commandsToSkipShell").
  static const Set<String> _skipShell = {
    'workbench.action.showCommands',
    'workbench.action.quickOpen',
    'workbench.action.terminal.toggleTerminal',
    'workbench.action.terminal.new',
    'workbench.action.toggleSidebarVisibility',
    'workbench.action.togglePanel',
    'workbench.view.explorer',
    'workbench.view.search',
    'workbench.view.scm',
    'workbench.view.extensions',
    'workbench.action.debug.start',
    'workbench.action.debug.run',
    'workbench.action.openSettings',
    'workbench.action.zoomIn',
    'workbench.action.zoomOut',
    'workbench.action.zoomReset',
    'workbench.action.toggleFullScreen',
    'workbench.action.toggleAssistant',
    'workbench.action.files.save',
    'workbench.action.nextEditor',
    'workbench.action.previousEditor',
  };

  /// Key handler used by terminal views; returns true when consumed.
  bool handleTerminalKey(KeyEvent e) {
    final String? id = commands.match(e);
    if (id == null || !_skipShell.contains(id)) return false;
    return commands.execute(id);
  }

  /// Global key handler (installed at the root of the widget tree).
  bool handleKey(KeyEvent e) {
    if (quickPick != null) return false;
    return commands.handleKey(e);
  }

  @override
  void dispose() {
    terminals.dispose();
    liveServer.stop();
    lsp.dispose();
    settings.saveNow();
    super.dispose();
  }
}
