import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/languages.dart';
import '../core/paths.dart';
import '../core/settings.dart';
import '../theme/ide_theme.dart';

enum ExtensionCategory { language, tool, theme, ai, other }

class ExtensionInfo {
  const ExtensionInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.icon,
    required this.color,
    this.features = const [],
    this.requirements = const [],
    this.version = '1.0.0',
    this.publisher = 'SmartIDE',
    this.core = false,
    this.remote = false,
    this.downloadUrl,
    this.languageIds = const [],
  });

  final String id;
  final String name;
  final String description;
  final ExtensionCategory category;
  final IconData icon;
  final Color color;
  final List<String> features;

  /// Tool ids from the Toolchain that power this extension.
  final List<String> requirements;
  final String version;
  final String publisher;

  /// Core extensions cannot be disabled.
  final bool core;

  /// Downloadable from the online catalog.
  final bool remote;
  final String? downloadUrl;
  final List<String> languageIds;
}

/// Built-in extensions. They are compiled into SmartIDE (each is only a few
/// kilobytes of configuration) and can be enabled or disabled at will.
const List<ExtensionInfo> builtInExtensions = [
  ExtensionInfo(
    id: 'smartide.python',
    name: 'Python',
    description: 'Rich Python support: highlighting, snippets, run with F5, Pyright IntelliSense and diagnostics.',
    category: ExtensionCategory.language,
    icon: Icons.code_rounded,
    color: Color(0xFF3B82C4),
    features: ['Syntax highlighting', 'Run current file (F5 / Ctrl+F5)', 'Snippets: def, class, for, try, ifmain…', 'IntelliSense & diagnostics via Pyright', 'Virtual environment friendly terminal'],
    requirements: ['python'],
    languageIds: ['python'],
  ),
  ExtensionInfo(
    id: 'smartide.cpp',
    name: 'C / C++',
    description: 'Compile and run C and C++ with GCC/MinGW or Clang, clangd IntelliSense.',
    category: ExtensionCategory.language,
    icon: Icons.memory_rounded,
    color: Color(0xFF00599C),
    features: ['Syntax highlighting for C, C++, headers', 'Build & run with gcc / g++ (C++20)', 'clangd completion, go to definition, diagnostics', 'Snippets: main, for, class, cout…'],
    requirements: ['gcc', 'g++'],
    languageIds: ['c', 'cpp'],
  ),
  ExtensionInfo(
    id: 'smartide.csharp',
    name: 'C#',
    description: '.NET development: run single files or projects, csharp-ls IntelliSense.',
    category: ExtensionCategory.language,
    icon: Icons.tag_rounded,
    color: Color(0xFF9B4F96),
    features: ['Syntax highlighting', 'dotnet run for .csproj or single .cs files (.NET 10)', 'Completion & diagnostics via csharp-ls', 'Snippets: Main, cw, prop, foreach…'],
    requirements: ['dotnet'],
    languageIds: ['csharp'],
  ),
  ExtensionInfo(
    id: 'smartide.go',
    name: 'Go',
    description: 'Go language support with gopls and go run.',
    category: ExtensionCategory.language,
    icon: Icons.directions_run_rounded,
    color: Color(0xFF00ADD8),
    features: ['Syntax highlighting', 'go run (module aware)', 'gopls IntelliSense, formatting, diagnostics', 'Snippets: main, iferr, forr, st…'],
    requirements: ['go'],
    languageIds: ['go'],
  ),
  ExtensionInfo(
    id: 'smartide.web',
    name: 'Web: HTML, CSS, JavaScript, TypeScript',
    description: 'Everything for the web: HTML/CSS/JS/TS highlighting, Emmet-style snippets, Node.js runner.',
    category: ExtensionCategory.language,
    icon: Icons.language_rounded,
    color: Color(0xFFE44D26),
    features: ['HTML5 boilerplate with "!"', 'CSS, SCSS, Less', 'Run JavaScript with Node.js, TypeScript with tsx', 'typescript-language-server & vscode-langservers support'],
    requirements: ['node'],
    languageIds: ['html', 'css', 'scss', 'less', 'javascript', 'typescript'],
  ),
  ExtensionInfo(
    id: 'smartide.liveserver',
    name: 'Live Server',
    description: 'Launch a local development server with live reload for static & dynamic pages.',
    category: ExtensionCategory.tool,
    icon: Icons.podcasts_rounded,
    color: Color(0xFF41B883),
    features: ['One click "Go Live" in the status bar', 'Auto reload on save', 'CSS hot swap', 'Directory listing', 'Alt+L Alt+O shortcut'],
  ),
  ExtensionInfo(
    id: 'smartide.git',
    name: 'Git',
    description: 'Source control: stage, commit, push, pull, branches, history and diffs.',
    category: ExtensionCategory.tool,
    icon: Icons.account_tree_rounded,
    color: Color(0xFFF14E32),
    features: ['Source Control view', 'Inline file decorations in the explorer', 'Branch switcher in the status bar', 'Commit history', 'Side-by-side diff'],
    requirements: ['git'],
    languageIds: ['gitignore'],
  ),
  ExtensionInfo(
    id: 'smartide.java',
    name: 'Java & Kotlin',
    description: 'Run Java single-source programs and Kotlin scripts.',
    category: ExtensionCategory.language,
    icon: Icons.coffee_rounded,
    color: Color(0xFFE76F00),
    features: ['Syntax highlighting', 'java Main.java (JDK 11+)', 'jdtls support', 'Snippets: main, sout, fori'],
    requirements: ['java'],
    languageIds: ['java', 'kotlin'],
  ),
  ExtensionInfo(
    id: 'smartide.rust',
    name: 'Rust',
    description: 'cargo run / rustc and rust-analyzer support.',
    category: ExtensionCategory.language,
    icon: Icons.settings_suggest_rounded,
    color: Color(0xFFDEA584),
    features: ['Syntax highlighting', 'cargo run or rustc', 'rust-analyzer IntelliSense', 'Snippets: main, fn, impl, match'],
    requirements: ['cargo'],
    languageIds: ['rust'],
  ),
  ExtensionInfo(
    id: 'smartide.dart',
    name: 'Dart & Flutter',
    description: 'Dart language server and runner.',
    category: ExtensionCategory.language,
    icon: Icons.flutter_dash_rounded,
    color: Color(0xFF0175C2),
    features: ['Syntax highlighting', 'dart run', 'Dart analysis server', 'Flutter widget snippets'],
    requirements: ['dart'],
    languageIds: ['dart'],
  ),
  ExtensionInfo(
    id: 'smartide.php',
    name: 'PHP',
    description: 'PHP highlighting, runner and Intelephense support.',
    category: ExtensionCategory.language,
    icon: Icons.php_rounded,
    color: Color(0xFF777BB4),
    requirements: ['php'],
    languageIds: ['php'],
  ),
  ExtensionInfo(
    id: 'smartide.ruby',
    name: 'Ruby',
    description: 'Ruby highlighting, runner and Solargraph support.',
    category: ExtensionCategory.language,
    icon: Icons.diamond_rounded,
    color: Color(0xFFCC342D),
    requirements: ['ruby'],
    languageIds: ['ruby'],
  ),
  ExtensionInfo(
    id: 'smartide.shell',
    name: 'PowerShell, Batch & Bash',
    description: 'Scripting languages for Windows and Unix shells.',
    category: ExtensionCategory.language,
    icon: Icons.terminal_rounded,
    color: Color(0xFF2671BE),
    features: ['Run .ps1, .bat, .cmd and .sh files', 'Syntax highlighting'],
    requirements: ['powershell'],
    languageIds: ['powershell', 'bat', 'shell'],
  ),
  ExtensionInfo(
    id: 'smartide.markdown',
    name: 'Markdown Preview',
    description: 'Live side-by-side Markdown preview.',
    category: ExtensionCategory.language,
    icon: Icons.article_rounded,
    color: Color(0xFF519ABA),
    features: ['Ctrl+K V opens preview to the side', 'Headings, lists, code blocks, quotes, links'],
    languageIds: ['markdown'],
  ),
  ExtensionInfo(
    id: 'smartide.todo',
    name: 'TODO Highlight',
    description: 'Highlights TODO, FIXME, HACK and NOTE markers in comments.',
    category: ExtensionCategory.tool,
    icon: Icons.checklist_rounded,
    color: Color(0xFFE5B567),
  ),
  ExtensionInfo(
    id: 'smartide.assistant',
    name: 'SmartIDE Assistant (Claude)',
    description: 'Chat with Claude about your code: explain, refactor, fix and generate.',
    category: ExtensionCategory.ai,
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFFD97757),
    features: ['Ctrl+Alt+I toggles the assistant', 'Sends the active file or selection as context', 'Streaming answers with copy & insert buttons', 'Bring your own Anthropic API key'],
  ),
  ExtensionInfo(
    id: 'smartide.themes',
    name: 'Theme Collection',
    description: '33 hand-tuned color themes: SmartIDE Claude, One Dark, Dracula, Tokyo Night, Catppuccin, Nord and more.',
    category: ExtensionCategory.theme,
    icon: Icons.palette_rounded,
    color: Color(0xFFBD93F9),
    core: true,
  ),
  ExtensionInfo(
    id: 'smartide.fonts',
    name: 'Programming Fonts',
    description: '25 coding fonts including JetBrains Mono, Cascadia Code, Fira Code, Victor Mono. Downloaded on demand.',
    category: ExtensionCategory.theme,
    icon: Icons.font_download_rounded,
    color: Color(0xFF7AA2F7),
    core: true,
  ),
];

/// Manages built-in and downloadable extensions.
class ExtensionService extends ChangeNotifier {
  ExtensionService(this.settings);

  final Settings settings;

  static const String catalogUrl = 'https://raw.githubusercontent.com/ozodmeofficial/smartide/main/extensions/catalog.json';

  final List<ExtensionInfo> remoteCatalog = [];
  final Set<String> installedRemote = {};
  final List<IdeTheme> extraThemes = [];
  final Map<String, List<Snippet>> extraSnippets = {};
  bool loadingCatalog = false;
  String? catalogError;

  List<ExtensionInfo> get all => [...builtInExtensions, ...remoteCatalog.where((e) => !builtInExtensions.any((b) => b.id == e.id))];

  bool isEnabled(String id) {
    final ExtensionInfo? e = all.where((x) => x.id == id).firstOrNull;
    if (e == null) return false;
    if (e.core) return true;
    if (e.remote) return installedRemote.contains(id) && !settings.disabledExtensions.contains(id);
    return !settings.disabledExtensions.contains(id);
  }

  bool isInstalled(String id) {
    final ExtensionInfo? e = all.where((x) => x.id == id).firstOrNull;
    if (e == null) return false;
    return !e.remote || installedRemote.contains(id);
  }

  bool isLanguageEnabled(LanguageDef l) => l.extensionId == null || isEnabled(l.extensionId!);

  void setEnabled(String id, bool enabled) {
    settings.update((s) {
      if (enabled) {
        s.disabledExtensions.remove(id);
      } else {
        s.disabledExtensions.add(id);
      }
    });
    notifyListeners();
  }

  /// Loads downloaded extensions (theme packs, snippet packs) from disk.
  Future<void> loadInstalled() async {
    extraThemes.clear();
    extraSnippets.clear();
    installedRemote.clear();
    final Directory dir = Directory(AppPaths.extensionsDir);
    if (!await dir.exists()) return;
    await for (final FileSystemEntity e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final Map<String, dynamic> j = jsonDecode(await e.readAsString()) as Map<String, dynamic>;
        _applyPackage(j);
        installedRemote.add(j['id'] as String);
      } catch (err) {
        debugPrint('extension ${e.path}: $err');
      }
    }
    notifyListeners();
  }

  void _applyPackage(Map<String, dynamic> j) {
    if (settings.disabledExtensions.contains(j['id'])) return;
    for (final dynamic t in (j['themes'] as List? ?? const [])) {
      final IdeTheme? theme = themeFromJson(t as Map<String, dynamic>);
      if (theme != null) extraThemes.add(theme);
    }
    final dynamic snippets = j['snippets'];
    if (snippets is Map) {
      snippets.forEach((lang, list) {
        for (final dynamic s in list as List) {
          extraSnippets.putIfAbsent(lang as String, () => []).add(Snippet('${s['prefix']}', '${s['label'] ?? s['prefix']}', '${s['body']}'));
        }
      });
    }
  }

  Future<void> fetchCatalog() async {
    if (loadingCatalog) return;
    loadingCatalog = true;
    catalogError = null;
    notifyListeners();
    try {
      final String body = await _get(catalogUrl);
      final List<dynamic> list = (jsonDecode(body) as Map<String, dynamic>)['extensions'] as List<dynamic>;
      remoteCatalog
        ..clear()
        ..addAll(list.map((e) => _remoteInfo(e as Map<String, dynamic>)));
    } catch (e) {
      catalogError = 'Could not reach the extension catalog. Check your internet connection.';
    }
    loadingCatalog = false;
    notifyListeners();
  }

  ExtensionInfo _remoteInfo(Map<String, dynamic> j) => ExtensionInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String? ?? '',
        category: ExtensionCategory.values.firstWhere((c) => c.name == j['category'], orElse: () => ExtensionCategory.other),
        icon: switch (j['category']) {
          'theme' => Icons.palette_rounded,
          'language' => Icons.code_rounded,
          _ => Icons.extension_rounded,
        },
        color: _hex(j['color'] as String?) ?? const Color(0xFF8A877C),
        features: (j['features'] as List?)?.cast<String>() ?? const [],
        version: j['version'] as String? ?? '1.0.0',
        publisher: j['publisher'] as String? ?? 'Community',
        remote: true,
        downloadUrl: j['url'] as String?,
      );

  Future<bool> install(ExtensionInfo e) async {
    if (e.downloadUrl == null) return false;
    try {
      final String body = await _get(e.downloadUrl!);
      final Map<String, dynamic> j = jsonDecode(body) as Map<String, dynamic>;
      j['id'] = e.id;
      await File(p.join(AppPaths.extensionsDir, '${e.id}.json')).writeAsString(jsonEncode(j));
      await loadInstalled();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> uninstall(String id) async {
    final File f = File(p.join(AppPaths.extensionsDir, '$id.json'));
    if (await f.exists()) await f.delete();
    await loadInstalled();
  }

  static Future<String> _get(String url) async {
    final HttpClient c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final HttpClientResponse r = await (await c.getUrl(Uri.parse(url))).close();
      if (r.statusCode != 200) throw HttpException('HTTP ${r.statusCode}');
      return await r.transform(utf8.decoder).join();
    } finally {
      c.close();
    }
  }

  static Color? _hex(String? s) {
    if (s == null) return null;
    String h = s.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    final int? v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }

  /// Parses a theme from the JSON format used by theme packs.
  static IdeTheme? themeFromJson(Map<String, dynamic> j) {
    Color c(String k, [Color? fallback]) => _hex(j[k] as String?) ?? fallback ?? const Color(0xFF888888);
    try {
      return IdeTheme.fromPalette(
        id: j['id'] as String,
        name: j['name'] as String,
        dark: j['dark'] as bool? ?? true,
        p: ThemePalette(
          bg: c('bg'),
          fg: c('fg'),
          accent: c('accent'),
          comment: c('comment'),
          keyword: c('keyword'),
          string: c('string'),
          number: c('number'),
          function: c('function'),
          type: c('type'),
          variable: c('variable', c('fg')),
          constant: _hex(j['constant'] as String?),
          tag: _hex(j['tag'] as String?),
          attr: _hex(j['attr'] as String?),
          operator: _hex(j['operator'] as String?),
          chrome: _hex(j['chrome'] as String?),
          surface: _hex(j['surface'] as String?),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
