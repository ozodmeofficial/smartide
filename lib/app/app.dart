import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ui/widgets.dart';
import '../ui/workbench.dart';
import 'ide.dart';

class SmartIdeApp extends StatelessWidget {
  const SmartIdeApp({super.key, required this.ide});

  final Ide ide;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ide),
        ChangeNotifierProvider.value(value: ide.settings),
        ChangeNotifierProvider.value(value: ide.workspace),
        ChangeNotifierProvider.value(value: ide.commands),
        ChangeNotifierProvider.value(value: ide.output),
        ChangeNotifierProvider.value(value: ide.notifications),
        ChangeNotifierProvider.value(value: ide.toolchain),
        ChangeNotifierProvider.value(value: ide.terminals),
        ChangeNotifierProvider.value(value: ide.fonts),
        ChangeNotifierProvider.value(value: ide.extensions),
        ChangeNotifierProvider.value(value: ide.git),
        ChangeNotifierProvider.value(value: ide.liveServer),
        ChangeNotifierProvider.value(value: ide.lsp),
        ChangeNotifierProvider.value(value: ide.search),
        ChangeNotifierProvider.value(value: ide.assistant),
      ],
      child: Consumer<Ide>(
        builder: (context, ide, _) {
          final theme = ide.effectiveTheme;
          return MaterialApp(
            title: 'SmartIDE',
            debugShowCheckedModeBanner: false,
            navigatorKey: ide.navigatorKey,
            theme: theme.toMaterial(uiFont: kUiFont),
            builder: (context, child) => _Zoom(scale: ide.settings.uiScale, child: child!),
            home: const Workbench(),
          );
        },
      ),
    );
  }
}

/// Scales the whole UI (Ctrl+= / Ctrl+-), like VS Code's window zoom.
class _Zoom extends StatelessWidget {
  const _Zoom({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if ((scale - 1).abs() < 0.01) return child;
    return LayoutBuilder(builder: (context, box) {
      final Size logical = Size(box.maxWidth / scale, box.maxHeight / scale);
      final MediaQueryData mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(size: logical),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: logical.width,
            maxWidth: logical.width,
            minHeight: logical.height,
            maxHeight: logical.height,
            child: Transform.scale(scale: scale, alignment: Alignment.topLeft, child: child),
          ),
        ),
      );
    });
  }
}
