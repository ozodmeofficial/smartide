import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'paths.dart';

enum AutoSaveMode { off, afterDelay, onFocusChange }

/// User settings, persisted as JSON in the app data directory. Every field
/// has a sensible default so a missing or partially written file never breaks
/// start-up.
class Settings extends ChangeNotifier {
  Settings();

  // Appearance
  String themeId = 'claude-dark';
  String editorFont = 'JetBrains Mono';
  double editorFontSize = 14;
  double lineHeight = 1.55;
  bool ligatures = true;
  double uiScale = 1.0;
  bool minimap = true;
  bool lineNumbers = true;
  bool highlightActiveLine = true;
  bool showBreadcrumbs = true;
  bool smoothCursor = true;

  // Editing
  int tabSize = 4;
  bool insertSpaces = true;
  bool wordWrap = false;
  bool autoClosingBrackets = true;
  bool formatOnSave = false;
  bool trimTrailingWhitespace = true;
  bool insertFinalNewline = true;
  AutoSaveMode autoSave = AutoSaveMode.afterDelay;
  int autoSaveDelayMs = 1200;

  // Terminal
  String defaultShell = 'auto';
  String terminalFont = 'JetBrains Mono';
  double terminalFontSize = 13;

  // Files
  List<String> excludePatterns = ['.git', 'node_modules', '__pycache__', '.dart_tool', 'build', '.idea', '.vs', 'bin', 'obj', '.venv', 'venv', 'target', 'dist'];
  bool confirmDelete = true;
  bool restoreLastWorkspace = true;

  // Live server
  int liveServerPort = 5500;

  // Extensions
  Set<String> disabledExtensions = {};

  // AI assistant
  String aiApiKey = '';
  String aiModel = 'claude-opus-5-5';

  // Workspace history (not shown in settings UI)
  List<String> recentFolders = [];
  String? lastFolder;
  double sidebarWidth = 268;
  double panelHeight = 260;
  double assistantWidth = 380;

  Timer? _saveTimer;

  static Future<Settings> load() async {
    final Settings s = Settings();
    final File f = File(AppPaths.settingsFile);
    if (await f.exists()) {
      try {
        final dynamic data = jsonDecode(await f.readAsString());
        if (data is Map<String, dynamic>) s.applyJson(data);
      } catch (e) {
        debugPrint('settings: failed to parse, using defaults: $e');
      }
    }
    return s;
  }

  void applyJson(Map<String, dynamic> j) {
    T v<T>(String key, T fallback) {
      final dynamic value = j[key];
      if (value is T) return value;
      if (T == double && value is num) return value.toDouble() as T;
      if (T == int && value is num) return value.toInt() as T;
      return fallback;
    }

    themeId = v('workbench.colorTheme', themeId);
    editorFont = v('editor.fontFamily', editorFont);
    editorFontSize = v('editor.fontSize', editorFontSize).clamp(8.0, 40.0);
    lineHeight = v('editor.lineHeight', lineHeight).clamp(1.0, 3.0);
    ligatures = v('editor.fontLigatures', ligatures);
    uiScale = v('window.zoom', uiScale).clamp(0.7, 1.8);
    minimap = v('editor.minimap.enabled', minimap);
    lineNumbers = v('editor.lineNumbers', lineNumbers);
    highlightActiveLine = v('editor.renderLineHighlight', highlightActiveLine);
    showBreadcrumbs = v('breadcrumbs.enabled', showBreadcrumbs);
    smoothCursor = v('editor.cursorSmoothCaretAnimation', smoothCursor);
    tabSize = v('editor.tabSize', tabSize).clamp(1, 12);
    insertSpaces = v('editor.insertSpaces', insertSpaces);
    wordWrap = v('editor.wordWrap', wordWrap);
    autoClosingBrackets = v('editor.autoClosingBrackets', autoClosingBrackets);
    formatOnSave = v('editor.formatOnSave', formatOnSave);
    trimTrailingWhitespace = v('files.trimTrailingWhitespace', trimTrailingWhitespace);
    insertFinalNewline = v('files.insertFinalNewline', insertFinalNewline);
    final String autoSaveName = v('files.autoSave', autoSave.name);
    autoSave = AutoSaveMode.values.firstWhere((m) => m.name == autoSaveName, orElse: () => autoSave);
    autoSaveDelayMs = v('files.autoSaveDelay', autoSaveDelayMs).clamp(200, 60000);
    defaultShell = v('terminal.integrated.defaultProfile', defaultShell);
    terminalFont = v('terminal.integrated.fontFamily', terminalFont);
    terminalFontSize = v('terminal.integrated.fontSize', terminalFontSize).clamp(8.0, 32.0);
    final dynamic excludes = j['files.exclude'];
    if (excludes is List) excludePatterns = excludes.whereType<String>().toList();
    confirmDelete = v('explorer.confirmDelete', confirmDelete);
    restoreLastWorkspace = v('window.restoreWorkspace', restoreLastWorkspace);
    liveServerPort = v('liveServer.port', liveServerPort).clamp(1024, 65535);
    final dynamic disabled = j['extensions.disabled'];
    if (disabled is List) disabledExtensions = disabled.whereType<String>().toSet();
    aiApiKey = v('assistant.apiKey', aiApiKey);
    aiModel = v('assistant.model', aiModel);
    final dynamic recent = j['state.recentFolders'];
    if (recent is List) recentFolders = recent.whereType<String>().toList();
    lastFolder = j['state.lastFolder'] as String?;
    sidebarWidth = v('state.sidebarWidth', sidebarWidth).clamp(170.0, 700.0);
    panelHeight = v('state.panelHeight', panelHeight).clamp(100.0, 900.0);
    assistantWidth = v('state.assistantWidth', assistantWidth).clamp(280.0, 800.0);
  }

  Map<String, dynamic> toJson() => {
        'workbench.colorTheme': themeId,
        'editor.fontFamily': editorFont,
        'editor.fontSize': editorFontSize,
        'editor.lineHeight': lineHeight,
        'editor.fontLigatures': ligatures,
        'window.zoom': uiScale,
        'editor.minimap.enabled': minimap,
        'editor.lineNumbers': lineNumbers,
        'editor.renderLineHighlight': highlightActiveLine,
        'breadcrumbs.enabled': showBreadcrumbs,
        'editor.cursorSmoothCaretAnimation': smoothCursor,
        'editor.tabSize': tabSize,
        'editor.insertSpaces': insertSpaces,
        'editor.wordWrap': wordWrap,
        'editor.autoClosingBrackets': autoClosingBrackets,
        'editor.formatOnSave': formatOnSave,
        'files.trimTrailingWhitespace': trimTrailingWhitespace,
        'files.insertFinalNewline': insertFinalNewline,
        'files.autoSave': autoSave.name,
        'files.autoSaveDelay': autoSaveDelayMs,
        'terminal.integrated.defaultProfile': defaultShell,
        'terminal.integrated.fontFamily': terminalFont,
        'terminal.integrated.fontSize': terminalFontSize,
        'files.exclude': excludePatterns,
        'explorer.confirmDelete': confirmDelete,
        'window.restoreWorkspace': restoreLastWorkspace,
        'liveServer.port': liveServerPort,
        'extensions.disabled': disabledExtensions.toList()..sort(),
        'assistant.apiKey': aiApiKey,
        'assistant.model': aiModel,
        'state.recentFolders': recentFolders,
        'state.lastFolder': lastFolder,
        'state.sidebarWidth': sidebarWidth,
        'state.panelHeight': panelHeight,
        'state.assistantWidth': assistantWidth,
      };

  /// Applies [mutate] and schedules a debounced save.
  void update(void Function(Settings s) mutate) {
    mutate(this);
    notifyListeners();
    _scheduleSave();
  }

  /// Persists layout-only values without rebuilding listeners.
  void updateSilently(void Function(Settings s) mutate) {
    mutate(this);
    _scheduleSave();
  }

  void addRecentFolder(String path) {
    recentFolders.remove(path);
    recentFolders.insert(0, path);
    if (recentFolders.length > 12) recentFolders = recentFolders.sublist(0, 12);
    lastFolder = path;
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), saveNow);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    try {
      final File f = File(AppPaths.settingsFile);
      final File tmp = File('${f.path}.tmp');
      await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('settings: save failed: $e');
    }
  }

  bool isExcluded(String name) => excludePatterns.contains(name);
}
