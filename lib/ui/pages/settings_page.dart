import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/ide.dart';
import '../../core/paths.dart';
import '../../core/settings.dart';
import '../../services/assistant_service.dart';
import '../../services/terminal_service.dart';
import '../../theme/fonts.dart';
import '../../theme/ide_theme.dart';
import '../widgets.dart';

enum _Cat { appearance, editor, fonts, terminal, files, assistant, about }

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _Cat _cat = _Cat.appearance;
  String _query = '';

  static const Map<_Cat, (String, IconData)> _cats = {
    _Cat.appearance: ('Appearance', Icons.palette_outlined),
    _Cat.editor: ('Text Editor', Icons.edit_note_rounded),
    _Cat.fonts: ('Fonts', Icons.font_download_outlined),
    _Cat.terminal: ('Terminal', Icons.terminal_rounded),
    _Cat.files: ('Files & Workspace', Icons.folder_outlined),
    _Cat.assistant: ('Assistant', Icons.auto_awesome_outlined),
    _Cat.about: ('About', Icons.info_outline_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Ide ide = context.watch<Ide>();
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
          child: Row(children: [
            Text('Settings', style: serifText(t, size: 26)),
            const SizedBox(width: 24),
            Expanded(
              child: IdeTextField(
                hint: 'Search settings',
                prefix: Icon(Icons.search_rounded, size: 16, color: t.textFaint),
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              ),
            ),
            const SizedBox(width: 12),
            AccentButton(
              label: 'Open settings.json',
              subtle: true,
              icon: Icons.data_object_rounded,
              onTap: () async {
                await ide.settings.saveNow();
                await ide.workspace.openFile(AppPaths.settingsFile);
              },
            ),
          ]),
        ),
        Container(height: 1, color: t.border),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_query.isEmpty)
              Container(
                width: 210,
                padding: const EdgeInsets.all(10),
                child: Column(children: [
                  for (final MapEntry<_Cat, (String, IconData)> e in _cats.entries)
                    HoverBox(
                      onTap: () => setState(() => _cat = e.key),
                      selected: _cat == e.key,
                      radius: 8,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      child: Row(children: [
                        Icon(e.value.$2, size: 17, color: _cat == e.key ? t.accent : t.textMuted),
                        const SizedBox(width: 10),
                        Text(e.value.$1, style: uiText(t, size: 13.5, color: _cat == e.key ? t.text : t.textMuted, weight: _cat == e.key ? FontWeight.w600 : null)),
                      ]),
                    ),
                ]),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 18, 28, 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _query.isEmpty ? _section(_cat, ide) : [for (final _Cat c in _Cat.values) ..._section(c, ide)],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  bool _match(String title, String desc) => _query.isEmpty || title.toLowerCase().contains(_query) || desc.toLowerCase().contains(_query);

  List<Widget> _filter(List<_Row> rows) => [for (final _Row r in rows) if (_match(r.title, r.description)) r];

  List<Widget> _section(_Cat cat, Ide ide) {
    final Settings s = ide.settings;
    final IdeTheme t = ide.effectiveTheme;
    switch (cat) {
      case _Cat.appearance:
        return [
          if (_query.isEmpty || 'color theme'.contains(_query)) ...[
            _heading(t, 'Color Theme', '${ide.allThemes.length} themes. Hover to preview, click to apply.'),
            _ThemeGrid(ide: ide),
            const SizedBox(height: 18),
          ],
          ..._filter([
            _Row('Zoom', 'Scale the whole interface (Ctrl+= / Ctrl+-).', _Slider(value: s.uiScale, min: 0.7, max: 1.6, divisions: 18, label: '${(s.uiScale * 100).round()}%', onChanged: (v) => s.update((x) => x.uiScale = v))),
            _Row('Minimap', 'Show a code overview on the right edge of the editor.', Switch(value: s.minimap, onChanged: (v) => s.update((x) => x.minimap = v))),
            _Row('Breadcrumbs', 'Show the file path above the editor.', Switch(value: s.showBreadcrumbs, onChanged: (v) => s.update((x) => x.showBreadcrumbs = v))),
            _Row('Line Numbers', 'Show line numbers in the gutter.', Switch(value: s.lineNumbers, onChanged: (v) => s.update((x) => x.lineNumbers = v))),
            _Row('Highlight Current Line', 'Tint the line containing the cursor.', Switch(value: s.highlightActiveLine, onChanged: (v) => s.update((x) => x.highlightActiveLine = v))),
          ]),
        ];
      case _Cat.editor:
        return [
          ..._filter([
            _Row('Font Size', 'Editor font size in pixels.', _Slider(value: s.editorFontSize, min: 9, max: 28, divisions: 19, label: '${s.editorFontSize.round()} px', onChanged: (v) => s.update((x) => x.editorFontSize = v.roundToDouble()))),
            _Row('Line Height', 'Multiplier of the font size.', _Slider(value: s.lineHeight, min: 1.1, max: 2.2, divisions: 22, label: s.lineHeight.toStringAsFixed(2), onChanged: (v) => s.update((x) => x.lineHeight = v))),
            _Row('Tab Size', 'Number of spaces a tab is equal to.', _Choice<int>(value: s.tabSize, options: const {2: '2', 4: '4', 8: '8'}, onChanged: (v) => s.update((x) => x.tabSize = v))),
            _Row('Insert Spaces', 'Insert spaces when pressing Tab.', Switch(value: s.insertSpaces, onChanged: (v) => s.update((x) => x.insertSpaces = v))),
            _Row('Word Wrap', 'Wrap long lines at the viewport width (Alt+Z).', Switch(value: s.wordWrap, onChanged: (v) => s.update((x) => x.wordWrap = v))),
            _Row('Auto Closing Brackets', 'Automatically close brackets and quotes.', Switch(value: s.autoClosingBrackets, onChanged: (v) => s.update((x) => x.autoClosingBrackets = v))),
            _Row('Font Ligatures', 'Render ligatures such as => and != as single glyphs (font dependent).', Switch(value: s.ligatures, onChanged: (v) => s.update((x) => x.ligatures = v))),
            _Row('Format On Save', 'Format the file with its language server when saving.', Switch(value: s.formatOnSave, onChanged: (v) => s.update((x) => x.formatOnSave = v))),
            _Row('Trim Trailing Whitespace', 'Remove trailing spaces when saving.', Switch(value: s.trimTrailingWhitespace, onChanged: (v) => s.update((x) => x.trimTrailingWhitespace = v))),
            _Row('Insert Final Newline', 'End files with a newline when saving.', Switch(value: s.insertFinalNewline, onChanged: (v) => s.update((x) => x.insertFinalNewline = v))),
            _Row('Auto Save', 'Save files automatically.', _Choice<AutoSaveMode>(value: s.autoSave, options: const {AutoSaveMode.off: 'Off', AutoSaveMode.afterDelay: 'After delay', AutoSaveMode.onFocusChange: 'On focus change'}, onChanged: (v) => s.update((x) => x.autoSave = v))),
          ]),
        ];
      case _Cat.fonts:
        return [
          if (_match('editor font family', 'programming fonts ligatures')) ...[
            _heading(t, 'Editor Font', 'Fonts download on first use (100–700 KB each) and are cached for offline use.'),
            _FontGrid(ide: ide, selected: s.editorFont, onSelect: (f) => s.update((x) => x.editorFont = f)),
            const SizedBox(height: 22),
          ],
          if (_match('terminal font family', 'terminal')) ...[
            _heading(t, 'Terminal Font', 'Font used by the integrated terminal.'),
            _Row('Terminal Font', '', _Choice<String>(value: s.terminalFont, options: {for (final CodeFont f in codeFonts) f.family: f.family}, onChanged: (v) => s.update((x) => x.terminalFont = v))),
          ],
        ];
      case _Cat.terminal:
        final TerminalService ts = ide.terminals;
        return [
          ..._filter([
            _Row(
              'Default Profile',
              'Shell used for new terminals. Detected on this machine: ${ts.profiles.map((p) => p.name).join(', ')}.',
              _Choice<String>(value: ts.profiles.any((p) => p.id == s.defaultShell) ? s.defaultShell : 'auto', options: {'auto': 'Automatic', for (final ShellProfile p in ts.profiles) p.id: p.name}, onChanged: (v) => s.update((x) => x.defaultShell = v)),
            ),
            _Row('Font Size', 'Terminal font size.', _Slider(value: s.terminalFontSize, min: 9, max: 24, divisions: 15, label: '${s.terminalFontSize.round()} px', onChanged: (v) => s.update((x) => x.terminalFontSize = v.roundToDouble()))),
            _Row('Live Server Port', 'Preferred port for the built-in Live Server.', _NumberField(value: s.liveServerPort, onChanged: (v) => s.update((x) => x.liveServerPort = v))),
          ]),
        ];
      case _Cat.files:
        return [
          ..._filter([
            _Row('Excluded Folders', 'Folder and file names hidden from the explorer, search and quick open (comma separated).',
                _TextSetting(value: s.excludePatterns.join(', '), onChanged: (v) => s.update((x) => x.excludePatterns = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()))),
            _Row('Confirm Delete', 'Ask before deleting files from the explorer.', Switch(value: s.confirmDelete, onChanged: (v) => s.update((x) => x.confirmDelete = v))),
            _Row('Restore Last Folder', 'Reopen the last folder when SmartIDE starts.', Switch(value: s.restoreLastWorkspace, onChanged: (v) => s.update((x) => x.restoreLastWorkspace = v))),
          ]),
        ];
      case _Cat.assistant:
        return [
          ..._filter([
            _Row('Anthropic API Key', 'Used by the SmartIDE Assistant. Stored locally in settings.json. Get one at console.anthropic.com.',
                _TextSetting(value: s.aiApiKey, obscure: true, hint: 'sk-ant-…', onChanged: (v) => s.update((x) => x.aiApiKey = v.trim()))),
            _Row('Model', 'Claude model used for chat.',
                _Choice<String>(value: s.aiModel, options: {for (final AssistantModel m in assistantModels) m.id: '${m.name} — ${m.note}'}, onChanged: (v) => s.update((x) => x.aiModel = v))),
          ]),
        ];
      case _Cat.about:
        if (!_match('about version', 'smartide')) return [];
        return [
          _heading(t, 'SmartIDE 1.0.0', 'A fast, friendly code editor for Windows built with Flutter.'),
          _Row('Settings file', AppPaths.settingsFile, AccentButton(label: 'Reveal', subtle: true, dense: true, onTap: () => Ide.revealInOs(AppPaths.settingsFile))),
          _Row('Platform', '${Platform.operatingSystem} ${Platform.operatingSystemVersion}', const SizedBox()),
          _Row('Dart', Platform.version.split(' ').first, const SizedBox()),
        ];
    }
  }

  Widget _heading(IdeTheme t, String title, String sub) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: uiText(t, size: 16, weight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(sub, style: uiText(t, size: 12.5, color: t.textMuted)),
        ]),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.title, this.description, this.control);

  final String title;
  final String description;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border.withValues(alpha: 0.6)))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: uiText(t, size: 13.5, weight: FontWeight.w600)),
            if (description.isNotEmpty) ...[const SizedBox(height: 3), Text(description, style: uiText(t, size: 12.5, color: t.textMuted))],
          ]),
        ),
        const SizedBox(width: 24),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: control),
      ]),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({required this.value, required this.min, required this.max, required this.divisions, required this.label, required this.onChanged});

  final double value, min, max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return SizedBox(
      width: 300,
      child: Row(children: [
        Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged)),
        SizedBox(width: 56, child: Text(label, textAlign: TextAlign.right, style: uiText(t, size: 12.5, color: t.textMuted))),
      ]),
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({required this.value, required this.options, required this.onChanged});

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: t.inputBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: t.border)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: options.containsKey(value) ? value : options.keys.first,
          isDense: true,
          dropdownColor: t.surface,
          borderRadius: BorderRadius.circular(10),
          style: uiText(t, size: 13),
          icon: Icon(Icons.expand_more_rounded, size: 18, color: t.textMuted),
          items: [for (final MapEntry<T, String> e in options.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _TextSetting extends StatefulWidget {
  const _TextSetting({required this.value, required this.onChanged, this.obscure = false, this.hint});

  final String value;
  final ValueChanged<String> onChanged;
  final bool obscure;
  final String? hint;

  @override
  State<_TextSetting> createState() => _TextSettingState();
}

class _TextSettingState extends State<_TextSetting> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return SizedBox(
      width: 320,
      child: IdeTextField(
        controller: _c,
        hint: widget.hint,
        obscure: widget.obscure && !_show,
        onChanged: widget.onChanged,
        suffix: widget.obscure
            ? IconBtn(icon: _show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 15, onTap: () => setState(() => _show = !_show), color: t.textMuted)
            : null,
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: IdeTextField(
        controller: TextEditingController(text: '$value'),
        onSubmitted: (v) {
          final int? n = int.tryParse(v);
          if (n != null) onChanged(n);
        },
      ),
    );
  }
}

class _ThemeGrid extends StatelessWidget {
  const _ThemeGrid({required this.ide});

  final Ide ide;

  @override
  Widget build(BuildContext context) {
    final IdeTheme cur = ide.theme;
    return Wrap(spacing: 12, runSpacing: 12, children: [
      for (final IdeTheme th in ide.allThemes) _ThemeCard(theme: th, selected: th.id == cur.id, onTap: () => ide.settings.update((s) => s.themeId = th.id)),
    ]);
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.theme, required this.selected, required this.onTap});

  final IdeTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final IdeTheme th = theme;
    Widget bar(Color c, double w) => Container(height: 5, width: w, margin: const EdgeInsets.only(bottom: 5), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)));
    return HoverBox(
      onTap: onTap,
      radius: 12,
      child: Container(
        width: 196,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? t.accent : t.border, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(
            height: 92,
            color: th.chrome,
            child: Row(children: [
              Container(width: 22, color: th.chrome, child: Column(children: [
                const SizedBox(height: 10),
                for (int i = 0; i < 3; i++) Container(width: 10, height: 10, margin: const EdgeInsets.only(bottom: 7), decoration: BoxDecoration(color: i == 0 ? th.accent : th.textFaint, borderRadius: BorderRadius.circular(3))),
              ])),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: th.editorBg, borderRadius: BorderRadius.circular(6), border: Border.all(color: th.border)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [bar(th.palette.keyword, 26), const SizedBox(width: 5), bar(th.palette.function, 40)]),
                    Row(children: [const SizedBox(width: 12), bar(th.palette.variable, 30), const SizedBox(width: 5), bar(th.palette.string, 50)]),
                    Row(children: [const SizedBox(width: 12), bar(th.palette.comment, 70)]),
                    Row(children: [bar(th.palette.type, 34), const SizedBox(width: 5), bar(th.palette.number, 18)]),
                  ]),
                ),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: t.surface,
            child: Row(children: [
              Expanded(child: Text(th.name, style: uiText(t, size: 12.5, weight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
              if (selected) Icon(Icons.check_circle_rounded, size: 15, color: t.accent),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _FontGrid extends StatelessWidget {
  const _FontGrid({required this.ide, required this.selected, required this.onSelect});

  final Ide ide;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final FontManager fm = context.watch<FontManager>();
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final CodeFont f in codeFonts)
        HoverBox(
          onTap: () {
            fm.ensure(f.family);
            onSelect(f.family);
          },
          radius: 10,
          child: Container(
            width: 272,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected == f.family ? t.accent : t.border, width: selected == f.family ? 2 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(f.family, style: uiText(t, size: 13, weight: FontWeight.w600))),
                if (fm.isLoading(f.family))
                  SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: t.accent))
                else if (fm.errorFor(f.family) != null)
                  Tooltip(message: fm.errorFor(f.family)!, child: Icon(Icons.error_outline_rounded, size: 15, color: t.error))
                else if (f.source == FontSource.download && !fm.isCached(f))
                  Icon(Icons.cloud_download_outlined, size: 15, color: t.textFaint)
                else if (selected == f.family)
                  Icon(Icons.check_circle_rounded, size: 15, color: t.accent),
              ]),
              const SizedBox(height: 2),
              Text(f.ligatures ? '${f.note} · ligatures' : f.note, style: uiText(t, size: 11, color: t.textFaint)),
              const SizedBox(height: 8),
              Text(
                'fn main() => x != 0 && y >= 1;',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(fontFamily: fm.isLoaded(f.family) ? f.family : null, fontFamilyFallback: const ['Consolas', 'monospace'], fontSize: 13.5, color: t.palette.function),
              ),
            ]),
          ),
        ),
    ]);
  }
}
