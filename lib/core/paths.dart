import 'dart:io';

import 'package:path/path.dart' as p;

/// Locations where SmartIDE keeps its own data.
class AppPaths {
  AppPaths._();

  static String? _dataDir;
  static String get dataDir => _dataDir!;
  static set dataDir(String v) => _dataDir = v;

  static Future<void> init() async {
    if (_dataDir != null) return;
    final Map<String, String> env = Platform.environment;
    String base;
    if (Platform.isWindows) {
      base = env['APPDATA'] ?? p.join(env['USERPROFILE'] ?? '.', 'AppData', 'Roaming');
      dataDir = p.join(base, 'SmartIDE');
    } else if (Platform.isMacOS) {
      dataDir = p.join(env['HOME'] ?? '.', 'Library', 'Application Support', 'SmartIDE');
    } else {
      base = env['XDG_CONFIG_HOME'] ?? p.join(env['HOME'] ?? '.', '.config');
      dataDir = p.join(base, 'smartide');
    }
    for (final String dir in [dataDir, fontsDir, extensionsDir]) {
      await Directory(dir).create(recursive: true);
    }
  }

  static String get settingsFile => p.join(dataDir, 'settings.json');
  static String get keybindingsFile => p.join(dataDir, 'keybindings.json');
  static String get stateFile => p.join(dataDir, 'state.json');
  static String get fontsDir => p.join(dataDir, 'fonts');
  static String get extensionsDir => p.join(dataDir, 'extensions');

  static String get homeDir =>
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? Directory.current.path;
}
