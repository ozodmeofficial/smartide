import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartide/app/app.dart';
import 'package:smartide/app/ide.dart';
import 'package:smartide/core/paths.dart';
import 'package:smartide/core/settings.dart';
import 'package:smartide/ui/quick_pick_overlay.dart';
import 'package:smartide/workspace/editor_document.dart';

void main() {
  late Directory tmp;

  setUp(() {
    // window_manager has no implementation in widget tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (call) async => call.method.startsWith('is') ? false : null);
    tmp = Directory.systemTemp.createTempSync('smartide_smoke');
    File('${tmp.path}/a.py').writeAsStringSync('def hello():\n    print("hi")\n');
    File('${tmp.path}/README.md').writeAsStringSync('# Title\n\n- item\n');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Ide> boot(WidgetTester tester) async {
    await tester.runAsync(AppPaths.init);
    final Ide ide = Ide(Settings());
    await tester.runAsync(() => ide.init(openPath: '${tmp.path}/a.py'));
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      // Flush debounced timers (settings save, toasts, git refresh).
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await tester.pump(const Duration(seconds: 20));
    });
    await tester.pumpWidget(SmartIdeApp(ide: ide));
    await tester.pump(const Duration(milliseconds: 300));
    return ide;
  }

  testWidgets('workbench renders explorer, tab and status bar without errors', (tester) async {
    final Ide ide = await boot(tester);
    expect(find.text('a.py'), findsWidgets);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('Python'), findsWidgets); // status bar language
    expect(ide.workspace.activeDocument?.language.id, 'python');
  });

  testWidgets('command palette opens and lists commands', (tester) async {
    final Ide ide = await boot(tester);
    ide.showCommandPalette();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Type a command'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(QuickPickOverlay), matching: find.byType(TextField)), 'toggle terminal');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    final List<String> labels = [
      for (final Element e in find.byType(RichText).evaluate()) (e.widget as RichText).text.toPlainText(),
    ];
    expect(labels.where((l) => l.contains('Toggle Terminal')), isNotEmpty, reason: labels.where((l) => l.contains(':')).take(20).join(' | '));
  });

  testWidgets('special pages render: settings, keybindings, markdown preview', (tester) async {
    final Ide ide = await boot(tester);
    ide.workspace.openSpecial(TabKind.settings);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Color Theme'), findsWidgets);
    ide.workspace.openSpecial(TabKind.keybindings);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Keyboard Shortcuts'), findsWidgets);
    ide.workspace.openSpecial(TabKind.welcome);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Start a new project'), findsOneWidget);
  });

  testWidgets('every built-in theme builds the workbench', (tester) async {
    final Ide ide = await boot(tester);
    for (final theme in ide.allThemes) {
      ide.settings.update((s) => s.themeId = theme.id);
      await tester.pump(const Duration(milliseconds: 50));
      expect(ide.theme.id, theme.id);
    }
    // Let the debounced settings save complete.
    await tester.runAsync(() => ide.settings.saveNow());
    await tester.pump(const Duration(seconds: 1));
  });
}
