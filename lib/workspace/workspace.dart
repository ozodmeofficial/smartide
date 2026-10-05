import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/languages.dart';
import '../core/settings.dart';
import 'editor_document.dart';

enum DiagnosticSeverity { error, warning, info, hint }

class Diagnostic {
  const Diagnostic({
    required this.severity,
    required this.message,
    required this.line,
    required this.column,
    this.endLine,
    this.endColumn,
    this.source,
  });

  final DiagnosticSeverity severity;
  final String message;

  /// 0-based line / column.
  final int line;
  final int column;
  final int? endLine;
  final int? endColumn;
  final String? source;
}

class FileNode {
  FileNode(this.path, this.isDir);

  final String path;
  final bool isDir;
  List<FileNode>? children;
  bool expanded = false;

  String get name => p.basename(path);
}

class EditorGroup {
  final List<EditorTab> tabs = [];
  int active = -1;

  EditorTab? get activeTab => active >= 0 && active < tabs.length ? tabs[active] : null;
}

/// Image extensions shown in the built-in viewer.
const Set<String> imageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.ico'};

/// Central state for the open folder and editors.
class Workspace extends ChangeNotifier {
  /// Notifies listeners after an external mutation of public state.
  void touch() => notifyListeners();

  Workspace(this.settings);

  final Settings settings;

  String? root;
  FileNode? tree;
  final List<EditorGroup> groups = [EditorGroup()];
  int activeGroupIndex = 0;
  final List<String> _recentlyClosed = [];
  final Map<String, List<Diagnostic>> diagnostics = {};
  final Map<String, String> gitStatus = {};

  StreamSubscription<FileSystemEvent>? _watcher;
  Timer? _refreshTimer;
  final Map<String, Timer> _autoSaveTimers = {};

  /// Hooks used by services (LSP, git) to observe documents.
  final List<void Function(EditorDocument doc)> onDocumentOpened = [];
  final List<void Function(EditorDocument doc)> onDocumentChanged = [];
  final List<void Function(EditorDocument doc)> onDocumentSaved = [];
  final List<void Function(EditorDocument doc)> onDocumentClosed = [];
  final List<VoidCallback> onFilesChanged = [];

  /// Returns true if a dirty document may be discarded. Set by the UI.
  Future<bool> Function(EditorDocument doc)? confirmDiscard;

  /// Asks the UI for a save path for untitled documents.
  Future<String?> Function(EditorDocument doc)? askSavePath;

  EditorGroup get activeGroup => groups[activeGroupIndex.clamp(0, groups.length - 1)];
  EditorTab? get activeTab => activeGroup.activeTab;
  EditorDocument? get activeDocument => activeTab?.document;
  bool get hasFolder => root != null;
  String get folderName => root == null ? 'No Folder' : p.basename(root!);

  Iterable<EditorDocument> get openDocuments sync* {
    final Set<String> seen = {};
    for (final EditorGroup g in groups) {
      for (final EditorTab t in g.tabs) {
        final EditorDocument? d = t.document;
        if (d != null && seen.add(d.id)) yield d;
      }
    }
  }

  int get dirtyCount => openDocuments.where((d) => d.isDirty).length;

  // ---------------------------------------------------------------- folders

  Future<void> openFolder(String path) async {
    final Directory dir = Directory(path);
    if (!await dir.exists()) return;
    root = p.normalize(dir.absolute.path);
    tree = FileNode(root!, true)..expanded = true;
    await loadChildren(tree!);
    settings.addRecentFolder(root!);
    _watch();
    notifyListeners();
    for (final VoidCallback cb in onFilesChanged) {
      cb();
    }
  }

  void closeFolder() {
    _watcher?.cancel();
    root = null;
    tree = null;
    gitStatus.clear();
    settings.update((s) => s.lastFolder = null);
    notifyListeners();
  }

  Future<void> loadChildren(FileNode node) async {
    final List<FileNode> out = [];
    try {
      await for (final FileSystemEntity e in Directory(node.path).list(followLinks: false)) {
        final String name = p.basename(e.path);
        if (settings.isExcluded(name) && name != '.github') continue;
        out.add(FileNode(e.path, e is Directory));
      }
    } catch (_) {}
    out.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    // Keep expansion state of existing children.
    final Map<String, FileNode> old = {for (final FileNode c in node.children ?? const []) c.path: c};
    for (int i = 0; i < out.length; i++) {
      final FileNode? prev = old[out[i].path];
      if (prev != null && prev.isDir == out[i].isDir) out[i] = prev;
    }
    node.children = out;
  }

  Future<void> toggleNode(FileNode node) async {
    if (!node.isDir) return;
    node.expanded = !node.expanded;
    if (node.expanded && node.children == null) await loadChildren(node);
    notifyListeners();
  }

  Future<void> collapseAll() async {
    void walk(FileNode n) {
      if (n != tree) n.expanded = false;
      n.children?.forEach(walk);
    }

    if (tree != null) walk(tree!);
    notifyListeners();
  }

  /// Expands the tree down to [path] so it can be revealed.
  Future<void> reveal(String path) async {
    if (tree == null || !p.isWithin(root!, path)) return;
    FileNode node = tree!;
    final List<String> parts = p.split(p.relative(path, from: root));
    for (int i = 0; i < parts.length - 1; i++) {
      node.children ??= [];
      if (node.children!.isEmpty) await loadChildren(node);
      final FileNode? next = node.children!.where((c) => c.name == parts[i]).firstOrNull;
      if (next == null) break;
      next.expanded = true;
      if (next.children == null) await loadChildren(next);
      node = next;
    }
    notifyListeners();
  }

  Future<void> refreshTree() async {
    if (tree == null) return;
    Future<void> walk(FileNode n) async {
      if (!n.isDir || !n.expanded) return;
      await loadChildren(n);
      for (final FileNode c in n.children!) {
        await walk(c);
      }
    }

    await walk(tree!);
    notifyListeners();
  }

  void _watch() {
    _watcher?.cancel();
    if (root == null) return;
    try {
      _watcher = Directory(root!).watch(recursive: true).listen((event) {
        final String rel = p.relative(event.path, from: root);
        final String first = p.split(rel).first;
        if (first == '.git' && !rel.endsWith('HEAD') && !rel.endsWith('index')) return;
        _refreshTimer?.cancel();
        _refreshTimer = Timer(const Duration(milliseconds: 350), () async {
          await refreshTree();
          for (final EditorDocument d in openDocuments) {
            if (await d.reloadIfChanged()) notifyListeners();
          }
          for (final VoidCallback cb in onFilesChanged) {
            cb();
          }
        });
      }, onError: (_) {});
    } catch (_) {
      // Watching is best effort (not supported on some network drives).
    }
  }

  // ---------------------------------------------------------------- editors

  EditorTab? _findTab(bool Function(EditorTab t) test, {int? groupIndex}) {
    final List<int> order = groupIndex != null ? [groupIndex] : List.generate(groups.length, (i) => i);
    for (final int gi in order) {
      final EditorGroup g = groups[gi];
      for (int i = 0; i < g.tabs.length; i++) {
        if (test(g.tabs[i])) return g.tabs[i];
      }
    }
    return null;
  }

  void _activate(EditorTab tab) {
    for (int gi = 0; gi < groups.length; gi++) {
      final int idx = groups[gi].tabs.indexOf(tab);
      if (idx >= 0) {
        groups[gi].active = idx;
        activeGroupIndex = gi;
        break;
      }
    }
    notifyListeners();
  }

  void activateTab(int group, int index) {
    if (group >= groups.length || index >= groups[group].tabs.length) return;
    groups[group].active = index;
    activeGroupIndex = group;
    notifyListeners();
  }

  void _insertTab(EditorTab tab, {bool preview = false}) {
    final EditorGroup g = activeGroup;
    if (preview) {
      final int existing = g.tabs.indexWhere((t) => t.preview && !t.isDirty);
      if (existing >= 0) {
        final EditorTab old = g.tabs[existing];
        g.tabs[existing] = tab..preview = true;
        g.active = existing;
        _disposeTabIfUnused(old);
        notifyListeners();
        return;
      }
    }
    tab.preview = preview;
    final int at = g.active < 0 ? g.tabs.length : g.active + 1;
    g.tabs.insert(at.clamp(0, g.tabs.length), tab);
    g.active = g.tabs.indexOf(tab);
    notifyListeners();
  }

  Future<EditorDocument?> openFile(String path, {int? line, int? column, bool preview = false}) async {
    path = p.normalize(path);
    final EditorTab? existing = _findTab((t) => t.path != null && p.equals(t.path!, path), groupIndex: activeGroupIndex) ??
        _findTab((t) => t.path != null && p.equals(t.path!, path));
    if (existing != null) {
      if (!preview) existing.preview = false;
      _activate(existing);
      if (line != null) existing.document?.goTo(line, column ?? 1);
      return existing.document;
    }
    final String ext = p.extension(path).toLowerCase();
    if (imageExtensions.contains(ext)) {
      _insertTab(EditorTab.special(TabKind.image, path: path), preview: preview);
      return null;
    }
    final File f = File(path);
    if (!await f.exists()) return null;
    if (await _looksBinary(f)) {
      _insertTab(EditorTab.special(TabKind.binary, path: path), preview: preview);
      return null;
    }
    final EditorDocument doc = await EditorDocument.open(path);
    _wireDocument(doc);
    _insertTab(EditorTab.text(doc), preview: preview);
    for (final void Function(EditorDocument) cb in onDocumentOpened) {
      cb(doc);
    }
    if (line != null) {
      // Wait a frame so the editor is attached before scrolling.
      Future<void>.delayed(const Duration(milliseconds: 60), () => doc.goTo(line, column ?? 1));
    }
    return doc;
  }

  static Future<bool> _looksBinary(File f) async {
    try {
      final RandomAccessFile raf = await f.open();
      final List<int> head = await raf.read(8000);
      await raf.close();
      return head.contains(0);
    } catch (_) {
      return false;
    }
  }

  EditorDocument newUntitled({String text = '', LanguageDef? language}) {
    final EditorDocument doc = EditorDocument.untitled(text: text, language: language);
    _wireDocument(doc);
    _insertTab(EditorTab.text(doc));
    for (final void Function(EditorDocument) cb in onDocumentOpened) {
      cb(doc);
    }
    return doc;
  }

  void openSpecial(TabKind kind, {String? path, Object? extra}) {
    final EditorTab tab = EditorTab.special(kind, path: path, extra: extra);
    final EditorTab? existing = _findTab((t) => t.id == tab.id);
    if (existing != null) {
      _activate(existing);
      return;
    }
    _insertTab(tab);
  }

  void pinPreview(EditorTab tab) {
    tab.preview = false;
    notifyListeners();
  }

  void _wireDocument(EditorDocument doc) {
    doc.onTextChanged = () {
      final EditorTab? t = _findTab((t) => t.document == doc);
      if (t != null && t.preview) {
        t.preview = false;
        notifyListeners();
      }
      for (final void Function(EditorDocument) cb in onDocumentChanged) {
        cb(doc);
      }
      _scheduleAutoSave(doc);
    };
    doc.addListener(notifyListeners);
  }

  void _scheduleAutoSave(EditorDocument doc) {
    if (settings.autoSave != AutoSaveMode.afterDelay || doc.isUntitled) return;
    _autoSaveTimers[doc.id]?.cancel();
    _autoSaveTimers[doc.id] = Timer(Duration(milliseconds: settings.autoSaveDelayMs), () {
      if (doc.isDirty) saveDocument(doc, auto: true);
    });
  }

  /// Saves every dirty document when the window loses focus (if enabled).
  void onWindowBlur() {
    if (settings.autoSave != AutoSaveMode.onFocusChange) return;
    for (final EditorDocument d in openDocuments) {
      if (d.isDirty && !d.isUntitled) saveDocument(d, auto: true);
    }
  }

  Future<bool> saveDocument(EditorDocument doc, {bool saveAs = false, bool auto = false}) async {
    String? target;
    if (doc.isUntitled || saveAs) {
      if (auto) return false;
      target = await askSavePath?.call(doc);
      if (target == null) return false;
    }
    try {
      await doc.save(
        asPath: target,
        trimTrailing: settings.trimTrailingWhitespace && !auto,
        finalNewline: settings.insertFinalNewline,
      );
    } catch (e) {
      debugPrint('save failed: $e');
      return false;
    }
    for (final void Function(EditorDocument) cb in onDocumentSaved) {
      cb(doc);
    }
    notifyListeners();
    return true;
  }

  Future<void> saveActive({bool saveAs = false}) async {
    final EditorDocument? d = activeDocument;
    if (d != null) await saveDocument(d, saveAs: saveAs);
  }

  Future<void> saveAll() async {
    for (final EditorDocument d in openDocuments.toList()) {
      if (d.isDirty) await saveDocument(d);
    }
  }

  Future<bool> closeTab(EditorTab tab, {bool force = false}) async {
    final EditorDocument? doc = tab.document;
    final bool lastViewOfDoc = doc != null && openTabsOf(doc).length == 1;
    if (!force && doc != null && doc.isDirty && lastViewOfDoc) {
      final bool ok = await confirmDiscard?.call(doc) ?? true;
      if (!ok) return false;
    }
    for (int gi = 0; gi < groups.length; gi++) {
      final EditorGroup g = groups[gi];
      final int idx = g.tabs.indexOf(tab);
      if (idx < 0) continue;
      g.tabs.removeAt(idx);
      if (g.active >= g.tabs.length) g.active = g.tabs.length - 1;
      if (idx < g.active) g.active--;
      if (g.tabs.isEmpty && groups.length > 1) {
        groups.removeAt(gi);
        activeGroupIndex = 0;
      }
      break;
    }
    if (tab.path != null) {
      _recentlyClosed.remove(tab.path);
      _recentlyClosed.add(tab.path!);
    }
    _disposeTabIfUnused(tab);
    notifyListeners();
    return true;
  }

  List<EditorTab> openTabsOf(EditorDocument doc) => [
        for (final EditorGroup g in groups)
          for (final EditorTab t in g.tabs)
            if (t.document == doc) t,
      ];

  void _disposeTabIfUnused(EditorTab tab) {
    final EditorDocument? doc = tab.document;
    if (doc == null || openTabsOf(doc).isNotEmpty) return;
    for (final void Function(EditorDocument) cb in onDocumentClosed) {
      cb(doc);
    }
    _autoSaveTimers.remove(doc.id)?.cancel();
    doc.removeListener(notifyListeners);
    if (doc.path != null) diagnostics.remove(doc.path);
    // Dispose after the frame so widgets can detach first.
    Future<void>.delayed(const Duration(milliseconds: 300), doc.dispose);
  }

  Future<void> closeActive() async {
    final EditorTab? t = activeTab;
    if (t != null) await closeTab(t);
  }

  Future<void> closeOthers(EditorTab keep) async {
    for (final EditorTab t in activeGroup.tabs.where((t) => t != keep && !t.pinned).toList()) {
      if (!await closeTab(t)) return;
    }
  }

  Future<void> closeAll() async {
    for (final EditorGroup g in groups.toList()) {
      for (final EditorTab t in g.tabs.toList()) {
        if (!await closeTab(t)) return;
      }
    }
  }

  Future<void> closeSaved() async {
    for (final EditorTab t in activeGroup.tabs.where((t) => !t.isDirty).toList()) {
      await closeTab(t);
    }
  }

  Future<void> reopenClosed() async {
    while (_recentlyClosed.isNotEmpty) {
      final String path = _recentlyClosed.removeLast();
      if (await File(path).exists()) {
        await openFile(path);
        return;
      }
    }
  }

  void cycleTab(int delta) {
    final EditorGroup g = activeGroup;
    if (g.tabs.isEmpty) return;
    g.active = (g.active + delta) % g.tabs.length;
    if (g.active < 0) g.active += g.tabs.length;
    notifyListeners();
  }

  void moveTab(int group, int from, int to) {
    final EditorGroup g = groups[group];
    if (from == to || from < 0 || from >= g.tabs.length) return;
    final EditorTab t = g.tabs.removeAt(from);
    g.tabs.insert(to.clamp(0, g.tabs.length), t);
    g.active = g.tabs.indexOf(t);
    notifyListeners();
  }

  void splitEditor() {
    final EditorTab? t = activeTab;
    if (groups.length >= 2) {
      activeGroupIndex = activeGroupIndex == 0 ? 1 : 0;
      notifyListeners();
      return;
    }
    final EditorGroup g = EditorGroup();
    groups.add(g);
    if (t != null) {
      g.tabs.add(t.document != null ? EditorTab.text(t.document!) : EditorTab.special(t.kind, path: t.path, extra: t.extra));
      g.active = 0;
    }
    activeGroupIndex = 1;
    notifyListeners();
  }

  void focusGroup(int i) {
    if (i < groups.length) {
      activeGroupIndex = i;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- file ops

  Future<String?> createFile(String dir, String name) async {
    final String path = p.join(dir, name);
    final File f = File(path);
    if (await f.exists() || await Directory(path).exists()) return null;
    await f.create(recursive: true);
    await refreshTree();
    await openFile(path);
    return path;
  }

  Future<String?> createFolder(String dir, String name) async {
    final String path = p.join(dir, name);
    if (await Directory(path).exists()) return null;
    await Directory(path).create(recursive: true);
    await refreshTree();
    return path;
  }

  Future<bool> rename(String path, String newName) async {
    final String target = p.join(p.dirname(path), newName);
    if (target == path) return true;
    try {
      if (await FileSystemEntity.isDirectory(path)) {
        await Directory(path).rename(target);
      } else {
        await File(path).rename(target);
      }
    } catch (_) {
      return false;
    }
    // Close tabs pointing at the old path and reopen at the new location.
    for (final EditorGroup g in groups) {
      for (final EditorTab t in g.tabs.toList()) {
        if (t.document != null && t.path != null && (p.equals(t.path!, path) || p.isWithin(path, t.path!))) {
          t.document!.path = p.equals(t.path!, path) ? target : p.join(target, p.relative(t.path!, from: path));
          t.document!.language = languageForPath(t.document!.path!);
        }
      }
    }
    await refreshTree();
    notifyListeners();
    return true;
  }

  Future<void> delete(String path) async {
    try {
      if (await FileSystemEntity.isDirectory(path)) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
    } catch (_) {}
    for (final EditorGroup g in groups) {
      for (final EditorTab t in g.tabs.toList()) {
        if (t.path != null && (p.equals(t.path!, path) || p.isWithin(path, t.path!))) {
          await closeTab(t, force: true);
        }
      }
    }
    await refreshTree();
  }

  Future<void> copyInto(String source, String targetDir) async {
    String name = p.basename(source);
    String target = p.join(targetDir, name);
    int n = 1;
    while (await FileSystemEntity.type(target) != FileSystemEntityType.notFound) {
      final String stem = p.basenameWithoutExtension(name);
      target = p.join(targetDir, '$stem copy${n > 1 ? ' $n' : ''}${p.extension(name)}');
      n++;
    }
    if (await FileSystemEntity.isDirectory(source)) {
      await _copyDir(Directory(source), Directory(target));
    } else {
      await File(source).copy(target);
    }
    await refreshTree();
  }

  static Future<void> _copyDir(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final FileSystemEntity e in from.list()) {
      final String dest = p.join(to.path, p.basename(e.path));
      if (e is Directory) {
        await _copyDir(e, Directory(dest));
      } else if (e is File) {
        await e.copy(dest);
      }
    }
  }

  // ---------------------------------------------------------------- diagnostics

  void setDiagnostics(String path, List<Diagnostic> list) {
    if (list.isEmpty) {
      diagnostics.remove(path);
    } else {
      diagnostics[path] = list;
    }
    notifyListeners();
  }

  int get errorCount => diagnostics.values.expand((l) => l).where((d) => d.severity == DiagnosticSeverity.error).length;
  int get warningCount => diagnostics.values.expand((l) => l).where((d) => d.severity == DiagnosticSeverity.warning).length;

  void setGitStatus(Map<String, String> status) {
    gitStatus
      ..clear()
      ..addAll(status);
    notifyListeners();
  }

  /// Every file in the workspace (respecting excludes), for quick open/search.
  Future<List<String>> listAllFiles({int limit = 20000}) async {
    if (root == null) return [];
    final List<String> out = [];
    final List<Directory> stack = [Directory(root!)];
    while (stack.isNotEmpty && out.length < limit) {
      final Directory d = stack.removeLast();
      try {
        await for (final FileSystemEntity e in d.list(followLinks: false)) {
          final String name = p.basename(e.path);
          if (settings.isExcluded(name)) continue;
          if (e is Directory) {
            stack.add(e);
          } else if (e is File) {
            out.add(e.path);
            if (out.length >= limit) break;
          }
        }
      } catch (_) {}
    }
    return out;
  }

  String relative(String path) => root == null ? path : p.relative(path, from: root);

  @override
  void dispose() {
    _watcher?.cancel();
    _refreshTimer?.cancel();
    for (final Timer t in _autoSaveTimers.values) {
      t.cancel();
    }
    super.dispose();
  }
}
