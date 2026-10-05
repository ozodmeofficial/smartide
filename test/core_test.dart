import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartide/app/quick_pick.dart';
import 'package:smartide/core/commands.dart';
import 'package:smartide/core/languages.dart';
import 'package:smartide/core/settings.dart';
import 'package:smartide/services/extension_service.dart';
import 'package:smartide/theme/fonts.dart';
import 'package:smartide/theme/themes.dart';
import 'package:smartide/ui/editor/code_editor_view.dart';

void main() {
  group('fuzzy matching', () {
    test('matches subsequences and ranks prefixes higher', () {
      expect(fuzzyScore('main.py', 'mp'), isNotNull);
      expect(fuzzyScore('main.py', 'xyz'), isNull);
      expect(fuzzyScore('editor_area.dart', 'edar')!, greaterThan(0));
      expect(fuzzyScore('main.py', 'main')!, greaterThan(fuzzyScore('domain.py', 'main')!));
    });

    test('indices highlight the matched characters', () {
      expect(fuzzyIndices('main.py', 'mp'), [0, 5]);
      expect(fuzzyIndices('hello', 'll'), [2, 3]);
    });
  });

  group('key bindings', () {
    test('parses VS Code style chords', () {
      final KeyCombo c = KeyCombo.parse('ctrl+shift+p')!;
      expect(c.ctrl, isTrue);
      expect(c.shift, isTrue);
      expect(c.key, LogicalKeyboardKey.keyP);
      expect(c.label, 'Ctrl+Shift+P');
      expect(KeyCombo.parse('ctrl+`')!.key, LogicalKeyboardKey.backquote);
      expect(KeyCombo.parse('f5')!.key, LogicalKeyboardKey.f5);
    });

    test('two-step chords and aliases', () {
      final Keybinding kb = Keybinding.parse('workbench.action.files.openFolder', 'ctrl+k ctrl+o')!;
      expect(kb.steps, hasLength(2));
      expect(kb.label, 'Ctrl+K Ctrl+O');
      expect(Keybinding.parse('workbench.action.quickOpen.e', 'ctrl+e')!.commandId, 'workbench.action.quickOpen');
    });

    test('all default bindings parse', () {
      defaultKeybindings.forEach((id, spec) {
        if (spec.contains('@')) return;
        expect(Keybinding.parse(id, spec), isNotNull, reason: '$id => $spec');
      });
    });
  });

  group('languages', () {
    test('detects languages by extension and file name', () {
      expect(languageForPath('C:/x/main.py').id, 'python');
      expect(languageForPath('/a/b/app.cpp').id, 'cpp');
      expect(languageForPath('/a/b/x.h').id, 'c');
      expect(languageForPath('Program.cs').id, 'csharp');
      expect(languageForPath('main.go').id, 'go');
      expect(languageForPath('index.html').id, 'html');
      expect(languageForPath('Dockerfile').id, 'dockerfile');
      expect(languageForPath('Makefile').id, 'makefile');
      expect(languageForPath('.gitignore').id, 'gitignore');
      expect(languageForPath('notes.unknownext').id, 'plaintext');
    });

    test('run commands quote paths with spaces', () {
      final LanguageDef py = languageById('python')!;
      final String cmd = py.run!(RunContext(file: '/my code/main.py', workspace: null, tools: {'python': 'py'}))!;
      expect(cmd, 'py -u "/my code/main.py"');
      final LanguageDef cpp = languageById('cpp')!;
      expect(cpp.run!(RunContext(file: '/p/a.cpp', workspace: null, tools: {}))!, contains('g++ -std=c++20'));
    });

    test('snippets have valid tab stops', () {
      for (final LanguageDef l in languages) {
        for (final Snippet s in l.snippets) {
          expect(s.body.contains(r'$'), isTrue, reason: '${l.id}:${s.prefix} has no tab stop');
        }
      }
    });
  });

  test('at least 20 themes and 10 fonts are available', () {
    expect(builtInThemes.length, greaterThanOrEqualTo(20));
    expect(builtInThemes.map((t) => t.id).toSet().length, builtInThemes.length, reason: 'theme ids must be unique');
    expect(codeFonts.length, greaterThanOrEqualTo(10));
    expect(languages.where((l) => l.run != null).length, greaterThanOrEqualTo(10));
  });

  test('settings survive a JSON round trip and clamp bad values', () {
    final Settings a = Settings()
      ..themeId = 'dracula'
      ..editorFontSize = 17
      ..wordWrap = true
      ..autoSave = AutoSaveMode.onFocusChange
      ..disabledExtensions = {'smartide.go'};
    final Settings b = Settings()..applyJson(a.toJson());
    expect(b.themeId, 'dracula');
    expect(b.editorFontSize, 17);
    expect(b.wordWrap, isTrue);
    expect(b.autoSave, AutoSaveMode.onFocusChange);
    expect(b.disabledExtensions, {'smartide.go'});
    final Settings c = Settings()..applyJson({'editor.fontSize': 500, 'editor.tabSize': 'x'});
    expect(c.editorFontSize, 40);
    expect(c.tabSize, 4);
  });

  test('applyRanges restyles exact character ranges in nested spans', () {
    const TextSpan span = TextSpan(style: TextStyle(color: Color(0xFF000000)), children: [
      TextSpan(text: 'def ', style: TextStyle(color: Color(0xFFFF0000))),
      TextSpan(text: 'hello():'),
    ]);
    final TextSpan out = applyRanges(span, [(4, 9, const TextStyle(decoration: TextDecoration.underline))]);
    final List<TextSpan> parts = out.children!.cast<TextSpan>();
    expect(parts.map((p) => p.text).join(), 'def hello():');
    final TextSpan hello = parts.firstWhere((p) => p.text == 'hello');
    expect(hello.style!.decoration, TextDecoration.underline);
    expect(parts.firstWhere((p) => p.text == 'def ').style!.color, const Color(0xFFFF0000));
  });

  test('online catalog theme packs parse into themes', () {
    final Map<String, dynamic> catalog = jsonDecode(File('extensions/catalog.json').readAsStringSync()) as Map<String, dynamic>;
    expect((catalog['extensions'] as List), isNotEmpty);
    for (final String f in ['themes-midnight', 'themes-daylight']) {
      final Map<String, dynamic> pack = jsonDecode(File('extensions/packs/$f.json').readAsStringSync()) as Map<String, dynamic>;
      for (final dynamic t in pack['themes'] as List) {
        expect(ExtensionService.themeFromJson(t as Map<String, dynamic>), isNotNull, reason: '${t['id']}');
      }
    }
  });
}
