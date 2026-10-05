import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A developer tool SmartIDE knows how to detect on the local machine.
class ToolInfo {
  ToolInfo({
    required this.id,
    required this.name,
    required this.candidates,
    required this.versionArgs,
    required this.installHint,
    this.url = '',
  });

  final String id;
  final String name;

  /// Executable names tried in order (e.g. `python`, `py`, `python3`).
  final List<String> candidates;
  final List<String> versionArgs;
  final String installHint;
  final String url;

  String? resolved;
  String? version;
  bool checked = false;

  bool get available => resolved != null;
}

/// Detects compilers, runtimes and helpers that are installed on the machine
/// so SmartIDE can adapt its run commands, terminals and extensions.
class Toolchain extends ChangeNotifier {
  Toolchain() {
    tools = [
      ToolInfo(id: 'python', name: 'Python', candidates: Platform.isWindows ? ['python', 'py', 'python3'] : ['python3', 'python'], versionArgs: ['--version'], installHint: 'winget install Python.Python.3.13', url: 'https://www.python.org/downloads/'),
      ToolInfo(id: 'gcc', name: 'GCC (C)', candidates: ['gcc'], versionArgs: ['--version'], installHint: 'winget install BrechtSanders.WinLibs.POSIX.UCRT  (MinGW-w64)', url: 'https://winlibs.com/'),
      ToolInfo(id: 'g++', name: 'G++ (C++)', candidates: ['g++', 'clang++'], versionArgs: ['--version'], installHint: 'winget install BrechtSanders.WinLibs.POSIX.UCRT  (MinGW-w64)', url: 'https://winlibs.com/'),
      ToolInfo(id: 'dotnet', name: '.NET SDK (C#)', candidates: ['dotnet'], versionArgs: ['--version'], installHint: 'winget install Microsoft.DotNet.SDK.10', url: 'https://dotnet.microsoft.com/download'),
      ToolInfo(id: 'go', name: 'Go', candidates: ['go'], versionArgs: ['version'], installHint: 'winget install GoLang.Go', url: 'https://go.dev/dl/'),
      ToolInfo(id: 'node', name: 'Node.js', candidates: ['node'], versionArgs: ['--version'], installHint: 'winget install OpenJS.NodeJS.LTS', url: 'https://nodejs.org/'),
      ToolInfo(id: 'git', name: 'Git', candidates: ['git'], versionArgs: ['--version'], installHint: 'winget install Git.Git', url: 'https://git-scm.com/download/win'),
      ToolInfo(id: 'java', name: 'Java (JDK)', candidates: ['java'], versionArgs: ['-version'], installHint: 'winget install Microsoft.OpenJDK.21', url: 'https://adoptium.net/'),
      ToolInfo(id: 'rustc', name: 'Rust', candidates: ['rustc'], versionArgs: ['--version'], installHint: 'winget install Rustlang.Rustup', url: 'https://rustup.rs/'),
      ToolInfo(id: 'cargo', name: 'Cargo', candidates: ['cargo'], versionArgs: ['--version'], installHint: 'winget install Rustlang.Rustup', url: 'https://rustup.rs/'),
      ToolInfo(id: 'dart', name: 'Dart', candidates: ['dart'], versionArgs: ['--version'], installHint: 'winget install Google.DartSDK', url: 'https://dart.dev/get-dart'),
      ToolInfo(id: 'php', name: 'PHP', candidates: ['php'], versionArgs: ['--version'], installHint: 'winget install PHP.PHP.8.4', url: 'https://windows.php.net/download/'),
      ToolInfo(id: 'ruby', name: 'Ruby', candidates: ['ruby'], versionArgs: ['--version'], installHint: 'winget install RubyInstallerTeam.Ruby.3.4', url: 'https://rubyinstaller.org/'),
      ToolInfo(id: 'powershell', name: 'PowerShell', candidates: Platform.isWindows ? ['pwsh', 'powershell'] : ['pwsh'], versionArgs: ['-NoProfile', '-Command', r'$PSVersionTable.PSVersion.ToString()'], installHint: 'winget install Microsoft.PowerShell', url: 'https://aka.ms/powershell'),
      ToolInfo(id: 'bash', name: 'Bash', candidates: ['bash'], versionArgs: ['--version'], installHint: 'Installed with Git for Windows', url: 'https://git-scm.com/download/win'),
    ];
  }

  late final List<ToolInfo> tools;
  bool scanning = false;
  DateTime? lastScan;

  ToolInfo? operator [](String id) => tools.where((t) => t.id == id).firstOrNull;

  /// Map used by run commands: tool id -> executable to invoke.
  Map<String, String> get resolvedMap => {
        for (final ToolInfo t in tools)
          if (t.resolved != null) t.id: t.resolved!,
      };

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    notifyListeners();
    await Future.wait(tools.map(_probe));
    scanning = false;
    lastScan = DateTime.now();
    notifyListeners();
  }

  Future<void> _probe(ToolInfo t) async {
    t.resolved = null;
    t.version = null;
    for (final String exe in t.candidates) {
      final String? path = await which(exe);
      if (path == null) continue;
      t.resolved = exe;
      try {
        final ProcessResult r = await Process.run(exe, t.versionArgs, runInShell: Platform.isWindows)
            .timeout(const Duration(seconds: 6));
        final String out = '${r.stdout}\n${r.stderr}'.trim();
        final RegExpMatch? m = RegExp(r'(?:version|v|go)\s*"?(\d+\.\d+(\.\d+)?)', caseSensitive: false).firstMatch(out) ??
            RegExp(r'(\d+\.\d+(\.\d+)?)').firstMatch(out);
        t.version = m?.group(1) ?? out.split('\n').first;
      } catch (_) {
        t.version = '?';
      }
      break;
    }
    t.checked = true;
  }

  static final Map<String, String?> _whichCache = {};

  /// Locates an executable on PATH without spawning a shell.
  static Future<String?> which(String exe) async {
    if (_whichCache.containsKey(exe)) return _whichCache[exe];
    final String pathVar = Platform.environment['PATH'] ?? Platform.environment['Path'] ?? '';
    final List<String> dirs = pathVar.split(Platform.isWindows ? ';' : ':');
    final List<String> exts = Platform.isWindows
        ? (Platform.environment['PATHEXT'] ?? '.EXE;.CMD;.BAT;.COM').toLowerCase().split(';')
        : [''];
    for (final String dir in dirs) {
      if (dir.isEmpty) continue;
      for (final String ext in exts) {
        final String candidate = '$dir${Platform.pathSeparator}$exe${exe.toLowerCase().endsWith(ext) ? '' : ext}';
        if (await File(candidate).exists()) {
          // The Windows Store "python.exe" alias opens the Store instead of
          // running Python; skip it so we can fall back to `py`.
          if (Platform.isWindows && candidate.toLowerCase().contains('windowsapps') && exe.startsWith('python')) {
            continue;
          }
          return _whichCache[exe] = candidate;
        }
      }
    }
    return _whichCache[exe] = null;
  }

  static void clearCache() => _whichCache.clear();
}
