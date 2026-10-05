import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;

import 'paths.dart';

/// A user-invokable action. Commands are shown in the command palette, the
/// menus and can be bound to keyboard shortcuts.
class Command {
  Command({
    required this.id,
    required this.title,
    required this.run,
    this.category = '',
    this.enabled,
    this.hidden = false,
  });

  final String id;
  final String title;
  final String category;
  final VoidCallback run;
  final bool Function()? enabled;
  final bool hidden;

  String get label => category.isEmpty ? title : '$category: $title';
  bool get isEnabled => enabled?.call() ?? true;
}

/// A parsed key chord such as `ctrl+shift+p`.
class KeyCombo {
  const KeyCombo(this.key, {this.ctrl = false, this.shift = false, this.alt = false, this.meta = false});

  final LogicalKeyboardKey key;
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;

  static KeyCombo? parse(String spec) {
    final List<String> parts = spec.toLowerCase().split('+').map((s) => s.trim()).toList();
    bool ctrl = false, shift = false, alt = false, meta = false;
    LogicalKeyboardKey? key;
    for (final String part in parts) {
      switch (part) {
        case 'ctrl':
        case 'control':
          ctrl = true;
        case 'shift':
          shift = true;
        case 'alt':
          alt = true;
        case 'meta':
        case 'cmd':
        case 'win':
          meta = true;
        default:
          key = _keyNames[part];
          if (key == null && part.length == 1) {
            final int code = part.codeUnitAt(0);
            if (code >= 0x61 && code <= 0x7a) key = LogicalKeyboardKey(0x00000000061 + code - 0x61);
            if (code >= 0x30 && code <= 0x39) key = LogicalKeyboardKey(0x00000000030 + code - 0x30);
          }
      }
    }
    if (key == null) return null;
    return KeyCombo(key, ctrl: ctrl, shift: shift, alt: alt, meta: meta);
  }

  SingleActivator get activator => SingleActivator(key, control: ctrl, shift: shift, alt: alt, meta: meta);

  bool matches(KeyEvent event) {
    final HardwareKeyboard hk = HardwareKeyboard.instance;
    LogicalKeyboardKey k = event.logicalKey;
    if (k == LogicalKeyboardKey.numpadEnter) k = LogicalKeyboardKey.enter;
    return k == key &&
        hk.isControlPressed == ctrl &&
        hk.isShiftPressed == shift &&
        hk.isAltPressed == alt &&
        hk.isMetaPressed == meta;
  }

  /// Human readable label, e.g. `Ctrl+Shift+P`.
  String get label {
    final List<String> out = [
      if (ctrl) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
      if (meta) 'Win',
      _labelFor(key),
    ];
    return out.join('+');
  }

  static String _labelFor(LogicalKeyboardKey key) {
    for (final MapEntry<String, LogicalKeyboardKey> e in _keyNames.entries) {
      if (e.value == key) {
        final String n = e.key;
        if (n.length == 1) return n.toUpperCase();
        return n[0].toUpperCase() + n.substring(1);
      }
    }
    final String l = key.keyLabel;
    return l.length == 1 ? l.toUpperCase() : l;
  }

  static final Map<String, LogicalKeyboardKey> _keyNames = {
    'enter': LogicalKeyboardKey.enter,
    'escape': LogicalKeyboardKey.escape,
    'esc': LogicalKeyboardKey.escape,
    'tab': LogicalKeyboardKey.tab,
    'space': LogicalKeyboardKey.space,
    'backspace': LogicalKeyboardKey.backspace,
    'delete': LogicalKeyboardKey.delete,
    'insert': LogicalKeyboardKey.insert,
    'home': LogicalKeyboardKey.home,
    'end': LogicalKeyboardKey.end,
    'pageup': LogicalKeyboardKey.pageUp,
    'pagedown': LogicalKeyboardKey.pageDown,
    'up': LogicalKeyboardKey.arrowUp,
    'down': LogicalKeyboardKey.arrowDown,
    'left': LogicalKeyboardKey.arrowLeft,
    'right': LogicalKeyboardKey.arrowRight,
    '`': LogicalKeyboardKey.backquote,
    '/': LogicalKeyboardKey.slash,
    '\\': LogicalKeyboardKey.backslash,
    ',': LogicalKeyboardKey.comma,
    '.': LogicalKeyboardKey.period,
    '=': LogicalKeyboardKey.equal,
    '-': LogicalKeyboardKey.minus,
    '[': LogicalKeyboardKey.bracketLeft,
    ']': LogicalKeyboardKey.bracketRight,
    ';': LogicalKeyboardKey.semicolon,
    "'": LogicalKeyboardKey.quote,
    'f1': LogicalKeyboardKey.f1,
    'f2': LogicalKeyboardKey.f2,
    'f3': LogicalKeyboardKey.f3,
    'f4': LogicalKeyboardKey.f4,
    'f5': LogicalKeyboardKey.f5,
    'f6': LogicalKeyboardKey.f6,
    'f7': LogicalKeyboardKey.f7,
    'f8': LogicalKeyboardKey.f8,
    'f9': LogicalKeyboardKey.f9,
    'f10': LogicalKeyboardKey.f10,
    'f11': LogicalKeyboardKey.f11,
    'f12': LogicalKeyboardKey.f12,
  };
}

/// VS Code compatible default key bindings (Windows layout).
const Map<String, String> defaultKeybindings = {
  // Workbench
  'workbench.action.showCommands': 'ctrl+shift+p',
  'workbench.action.showCommands.f1': 'f1',
  'workbench.action.quickOpen': 'ctrl+p',
  'workbench.action.quickOpen.e': 'ctrl+e',
  'workbench.action.gotoLine': 'ctrl+g',
  'workbench.action.toggleSidebarVisibility': 'ctrl+b',
  'workbench.action.togglePanel': 'ctrl+j',
  'workbench.action.terminal.toggleTerminal': 'ctrl+`',
  'workbench.action.terminal.new': 'ctrl+shift+`',
  'workbench.view.explorer': 'ctrl+shift+e',
  'workbench.view.search': 'ctrl+shift+f',
  'workbench.view.scm': 'ctrl+shift+g',
  'workbench.view.debug': 'ctrl+shift+d',
  'workbench.view.extensions': 'ctrl+shift+x',
  'workbench.actions.view.problems': 'ctrl+shift+m',
  'workbench.action.openSettings': 'ctrl+,',
  'workbench.action.selectTheme': 'ctrl+k ctrl+t',
  'workbench.action.zoomIn': 'ctrl+=',
  'workbench.action.zoomOut': 'ctrl+-',
  'workbench.action.zoomReset': 'ctrl+0',
  'workbench.action.toggleFullScreen': 'f11',
  'workbench.action.toggleZenMode': 'ctrl+k z',
  'workbench.action.toggleAssistant': 'ctrl+alt+i',
  // Files
  'workbench.action.files.newUntitledFile': 'ctrl+n',
  'workbench.action.files.openFile': 'ctrl+o',
  'workbench.action.files.openFolder': 'ctrl+k ctrl+o',
  'workbench.action.files.save': 'ctrl+s',
  'workbench.action.files.saveAs': 'ctrl+shift+s',
  'workbench.action.files.saveAll': 'ctrl+k s',
  'workbench.action.closeActiveEditor': 'ctrl+w',
  'workbench.action.closeActiveEditor.f4': 'ctrl+f4',
  'workbench.action.closeAllEditors': 'ctrl+k ctrl+w',
  'workbench.action.reopenClosedEditor': 'ctrl+shift+t',
  'workbench.action.nextEditor': 'ctrl+tab',
  'workbench.action.previousEditor': 'ctrl+shift+tab',
  'workbench.action.nextEditor.pgdn': 'ctrl+pagedown',
  'workbench.action.previousEditor.pgup': 'ctrl+pageup',
  'workbench.action.splitEditor': 'ctrl+\\',
  'workbench.action.newWindow': 'ctrl+shift+n',
  // Editor
  'editor.action.addSelectionToNextFindMatch': 'ctrl+d',
  'editor.action.copyLinesDownAction': 'shift+alt+down',
  'editor.action.copyLinesUpAction': 'shift+alt+up',
  'editor.action.formatDocument': 'shift+alt+f',
  'editor.action.triggerSuggest': 'ctrl+space',
  'editor.action.revealDefinition': 'f12',
  'editor.action.showHover': 'ctrl+k ctrl+i',
  'editor.action.rename': 'f2',
  'editor.action.insertLineAfter': 'ctrl+enter',
  'editor.action.insertLineBefore': 'ctrl+shift+enter',
  'editor.action.jumpToBracket': 'ctrl+shift+\\',
  'editor.action.indentLines': 'ctrl+]',
  'editor.action.outdentLines': 'ctrl+[',
  'editor.action.wordWrap': 'alt+z',
  'editor.action.marker.next': 'f8',
  'editor.action.marker.prev': 'shift+f8',
  'editor.fold': 'ctrl+shift+[',
  'editor.unfold': 'ctrl+shift+]',
  // Run
  'workbench.action.debug.run': 'ctrl+f5',
  'workbench.action.debug.start': 'f5',
  'workbench.action.debug.stop': 'shift+f5',
  'workbench.action.tasks.build': 'ctrl+shift+b',
  'liveServer.toggle': 'alt+l alt+o',
  // Git
  'git.commit': 'ctrl+enter@scm',
};

/// A keybinding entry, possibly a two-step chord (`ctrl+k ctrl+o`).
class Keybinding {
  Keybinding(this.commandId, this.steps);

  final String commandId;
  final List<KeyCombo> steps;

  String get label => steps.map((s) => s.label).join(' ');

  static Keybinding? parse(String commandId, String spec) {
    if (spec.contains('@')) return null; // context specific, handled by views
    final List<KeyCombo> steps = [];
    for (final String part in spec.trim().split(RegExp(r'\s+'))) {
      final KeyCombo? combo = KeyCombo.parse(part);
      if (combo == null) return null;
      steps.add(combo);
    }
    if (steps.isEmpty) return null;
    return Keybinding(_baseId(commandId), steps);
  }

  /// Aliases like `workbench.action.quickOpen.e` map back to the real command.
  static String _baseId(String id) {
    const Set<String> aliasSuffixes = {'.f1', '.e', '.f4', '.pgdn', '.pgup'};
    for (final String s in aliasSuffixes) {
      if (id.endsWith(s)) return id.substring(0, id.length - s.length);
    }
    return id;
  }
}

/// Registry of all commands and the active keybinding table.
class CommandRegistry extends ChangeNotifier {
  final Map<String, Command> _commands = {};
  final List<Keybinding> _bindings = [];
  Map<String, String> userOverrides = {};

  /// When the first step of a chord was pressed, holds the candidates.
  List<Keybinding>? _pendingChord;
  KeyCombo? pendingChordFirst;

  Iterable<Command> get all => _commands.values.where((c) => !c.hidden);
  Command? operator [](String id) => _commands[id];

  void register(Command c) => _commands[c.id] = c;

  void registerAll(Iterable<Command> cs) {
    for (final Command c in cs) {
      register(c);
    }
    notifyListeners();
  }

  bool execute(String id) {
    final Command? c = _commands[id];
    if (c == null || !c.isEnabled) return false;
    c.run();
    return true;
  }

  Future<void> loadKeybindings() async {
    try {
      final File f = File(AppPaths.keybindingsFile);
      if (await f.exists()) {
        final dynamic data = jsonDecode(await f.readAsString());
        if (data is List) {
          // VS Code format: [{ "key": "ctrl+x", "command": "id" }]
          userOverrides = {
            for (final dynamic e in data)
              if (e is Map && e['key'] is String && e['command'] is String) e['command'] as String: e['key'] as String,
          };
        }
      }
    } catch (e) {
      debugPrint('keybindings: $e');
    }
    _rebuild();
  }

  Future<void> setUserBinding(String commandId, String? spec) async {
    if (spec == null) {
      userOverrides.remove(commandId);
    } else {
      userOverrides[commandId] = spec;
    }
    _rebuild();
    final List<Map<String, String>> out = [
      for (final MapEntry<String, String> e in userOverrides.entries) {'key': e.value, 'command': e.key},
    ];
    await File(AppPaths.keybindingsFile).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  }

  void _rebuild() {
    _bindings.clear();
    final Map<String, String> merged = {...defaultKeybindings, ...userOverrides};
    merged.forEach((id, spec) {
      final Keybinding? kb = Keybinding.parse(id, spec);
      if (kb != null) _bindings.add(kb);
    });
    notifyListeners();
  }

  /// First keybinding label for a command, for menus and the palette.
  String? shortcutFor(String commandId) {
    for (final Keybinding kb in _bindings) {
      if (kb.commandId == commandId) return kb.label;
    }
    return null;
  }

  /// Handles a raw key event. Returns true if a command was triggered or a
  /// chord is in progress.
  bool handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (_isModifier(event.logicalKey)) return false;
    if (_pendingChord != null) {
      final List<Keybinding> candidates = _pendingChord!;
      _pendingChord = null;
      pendingChordFirst = null;
      notifyListeners();
      for (final Keybinding kb in candidates) {
        if (kb.steps.length > 1 && kb.steps[1].matches(event)) {
          return execute(kb.commandId) || true;
        }
      }
      return true; // swallow the unmatched second key like VS Code
    }
    final List<Keybinding> chordStarts = [];
    for (final Keybinding kb in _bindings) {
      if (!kb.steps.first.matches(event)) continue;
      if (kb.steps.length == 1) {
        if (execute(kb.commandId)) return true;
      } else {
        chordStarts.add(kb);
      }
    }
    if (chordStarts.isNotEmpty) {
      _pendingChord = chordStarts;
      pendingChordFirst = chordStarts.first.steps.first;
      notifyListeners();
      return true;
    }
    return false;
  }

  static bool _isModifier(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.controlLeft ||
      k == LogicalKeyboardKey.controlRight ||
      k == LogicalKeyboardKey.shiftLeft ||
      k == LogicalKeyboardKey.shiftRight ||
      k == LogicalKeyboardKey.altLeft ||
      k == LogicalKeyboardKey.altRight ||
      k == LogicalKeyboardKey.metaLeft ||
      k == LogicalKeyboardKey.metaRight;

  List<Keybinding> get bindings => List.unmodifiable(_bindings);

  /// Command bound to [event] as a single-step shortcut, if any.
  String? match(KeyEvent event) {
    if (event is! KeyDownEvent) return null;
    for (final Keybinding kb in _bindings) {
      if (kb.steps.length == 1 && kb.steps.first.matches(event)) return kb.commandId;
    }
    return null;
  }
}
