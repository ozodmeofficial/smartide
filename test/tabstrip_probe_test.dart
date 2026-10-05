import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartide/app/app.dart';
import 'package:smartide/app/ide.dart';
import 'package:smartide/core/paths.dart';
import 'package:smartide/core/settings.dart';

void main() {
  testWidgets('tab title renders', (tester) async {
    final Directory tmp = Directory.systemTemp.createTempSync('sid');
    File('${tmp.path}/a.py').writeAsStringSync('print(1)\n');
    await tester.runAsync(() async {
      await AppPaths.init();
    });
    final Ide ide = Ide(Settings());
    await tester.runAsync(() async {
      await ide.workspace.openFolder(tmp.path);
      await ide.workspace.openFile('${tmp.path}/a.py');
    });
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(SmartIdeApp(ide: ide));
    await tester.pump(const Duration(milliseconds: 500));
    final Finder f = find.text('a.py');
    debugPrint('found a.py: ${f.evaluate().length}');
    for (final e in f.evaluate()) {
      final RenderBox b = e.renderObject! as RenderBox;
      debugPrint('  at ${b.localToGlobal(Offset.zero)} size ${b.size} attached=${b.attached}');
      e.visitAncestorElements((a) {
        if (a.widget is Opacity) debugPrint('   opacity ${(a.widget as Opacity).opacity}');
        return true;
      });
    }
  });
}
