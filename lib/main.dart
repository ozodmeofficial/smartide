import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/ide.dart';
import 'core/paths.dart';
import 'core/settings.dart';
import 'theme/themes.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPaths.init();
  final Settings settings = await Settings.load();
  final Ide ide = Ide(settings);

  await windowManager.ensureInitialized();
  final Color bg = themeById(settings.themeId).chrome;
  final WindowOptions options = WindowOptions(
    title: 'SmartIDE',
    size: const Size(1440, 900),
    minimumSize: const Size(760, 480),
    center: true,
    backgroundColor: bg,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  // Path passed on the command line ("smartide.exe C:\code\project") or via
  // the Explorer context menu.
  final String? openPath = args.where((a) => !a.startsWith('-')).map((a) => a.replaceAll('"', '')).where((a) => FileSystemEntity.typeSync(a) != FileSystemEntityType.notFound).firstOrNull;

  runApp(SmartIdeApp(ide: ide));
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await ide.init(openPath: openPath);
}
