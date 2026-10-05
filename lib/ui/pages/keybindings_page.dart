import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/ide.dart';
import '../../core/commands.dart';
import '../../theme/ide_theme.dart';
import '../widgets.dart';

class KeybindingsPage extends StatefulWidget {
  const KeybindingsPage({super.key});

  @override
  State<KeybindingsPage> createState() => _KeybindingsPageState();
}

class _KeybindingsPageState extends State<KeybindingsPage> {
  String _query = '';
  String? _recording;
  String? _recorded;
  final FocusNode _recordFocus = FocusNode();

  @override
  void dispose() {
    _recordFocus.dispose();
    super.dispose();
  }

  static String? _spec(KeyEvent e) {
    final LogicalKeyboardKey k = e.logicalKey;
    final Set<LogicalKeyboardKey> mods = {
      LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight,
    };
    if (mods.contains(k)) return null;
    final HardwareKeyboard hk = HardwareKeyboard.instance;
    String name = k.keyLabel.toLowerCase();
    const Map<String, String> rename = {'arrow up': 'up', 'arrow down': 'down', 'arrow left': 'left', 'arrow right': 'right', 'page up': 'pageup', 'page down': 'pagedown'};
    name = rename[name] ?? name;
    if (name.isEmpty) return null;
    return [if (hk.isControlPressed) 'ctrl', if (hk.isShiftPressed) 'shift', if (hk.isAltPressed) 'alt', if (hk.isMetaPressed) 'meta', name].join('+');
  }

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Ide ide = context.watch<Ide>();
    final CommandRegistry reg = context.watch<CommandRegistry>();
    final List<Command> cmds = reg.all.where((c) => _query.isEmpty || c.label.toLowerCase().contains(_query) || c.id.contains(_query) || (reg.shortcutFor(c.id) ?? '').toLowerCase().contains(_query)).toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
        child: Row(children: [
          Text('Keyboard Shortcuts', style: serifText(t, size: 26)),
          const SizedBox(width: 24),
          Expanded(child: IdeTextField(hint: 'Type to search commands or keys', prefix: Icon(Icons.search_rounded, size: 16, color: t.textFaint), onChanged: (v) => setState(() => _query = v.toLowerCase()))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text('Shortcuts follow Visual Studio Code. Double-click a row to change its key binding.', style: uiText(t, size: 12.5, color: t.textMuted)),
      ),
      const SizedBox(height: 10),
      Container(height: 1, color: t.border),
      Expanded(
        child: ListView.builder(
          itemCount: cmds.length,
          itemExtent: 36,
          itemBuilder: (context, i) {
            final Command c = cmds[i];
            final String? key = reg.shortcutFor(c.id);
            final bool rec = _recording == c.id;
            final bool custom = reg.userOverrides.containsKey(c.id);
            return HoverBox(
              radius: 0,
              selected: rec,
              onDoubleTap: () {
                setState(() {
                  _recording = c.id;
                  _recorded = null;
                });
                _recordFocus.requestFocus();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(children: [
                  Expanded(flex: 5, child: Text(c.label, style: uiText(t, size: 13), overflow: TextOverflow.ellipsis)),
                  Expanded(
                    flex: 3,
                    child: rec
                        ? Focus(
                            focusNode: _recordFocus,
                            onKeyEvent: (node, e) {
                              if (e is! KeyDownEvent) return KeyEventResult.handled;
                              if (e.logicalKey == LogicalKeyboardKey.escape) {
                                setState(() => _recording = null);
                                return KeyEventResult.handled;
                              }
                              if (e.logicalKey == LogicalKeyboardKey.enter && _recorded != null) {
                                reg.setUserBinding(c.id, _recorded);
                                setState(() => _recording = null);
                                return KeyEventResult.handled;
                              }
                              final String? s = _spec(e);
                              if (s != null) setState(() => _recorded = s);
                              return KeyEventResult.handled;
                            },
                            child: Text(_recorded == null ? 'Press desired key combination, then Enter' : '${KeyCombo.parse(_recorded!)?.label ?? _recorded}  ⏎',
                                style: uiText(t, size: 12.5, color: t.accent)),
                          )
                        : (key == null ? Text('—', style: uiText(t, color: t.textFaint)) : Align(alignment: Alignment.centerLeft, child: Kbd(key, small: true))),
                  ),
                  Expanded(flex: 3, child: Text(c.id, style: uiText(t, size: 11.5, color: t.textFaint), overflow: TextOverflow.ellipsis)),
                  SizedBox(
                    width: 60,
                    child: custom
                        ? IconBtn(icon: Icons.restart_alt_rounded, tooltip: 'Reset to default', size: 15, onTap: () => reg.setUserBinding(c.id, null))
                        : IconBtn(icon: Icons.edit_outlined, tooltip: 'Change key binding', size: 15, onTap: () {
                            setState(() {
                              _recording = c.id;
                              _recorded = null;
                            });
                            _recordFocus.requestFocus();
                          }),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
      Container(height: 1, color: t.border),
      Padding(
        padding: const EdgeInsets.all(10),
        child: Text('${cmds.length} commands · user overrides are stored in keybindings.json', style: uiText(t, size: 12, color: ide.effectiveTheme.textFaint)),
      ),
    ]);
  }
}
