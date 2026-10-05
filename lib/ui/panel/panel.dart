import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../../app/ide.dart';
import '../../services/output_service.dart';
import '../../services/terminal_service.dart';
import '../../theme/fonts.dart';
import '../../theme/ide_theme.dart';
import '../../workspace/workspace.dart';
import '../widgets.dart';

class BottomPanel extends StatelessWidget {
  const BottomPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Ide ide = context.watch<Ide>();
    final Workspace ws = context.watch<Workspace>();
    final int problems = ws.errorCount + ws.warningCount;
    return Card2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 36,
          child: Row(children: [
            const SizedBox(width: 8),
            _PanelTab(label: 'Problems', badge: problems == 0 ? null : '$problems', selected: ide.panelTab == PanelTab.problems, onTap: () => ide.showPanel(PanelTab.problems)),
            _PanelTab(label: 'Output', selected: ide.panelTab == PanelTab.output, onTap: () => ide.showPanel(PanelTab.output)),
            _PanelTab(label: 'Terminal', selected: ide.panelTab == PanelTab.terminal, onTap: () => ide.showPanel(PanelTab.terminal)),
            const Spacer(),
            if (ide.panelTab == PanelTab.terminal) ..._terminalActions(context, ide),
            if (ide.panelTab == PanelTab.output) ..._outputActions(context, ide),
            IconBtn(
              icon: ide.panelMaximized ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
              tooltip: ide.panelMaximized ? 'Restore Panel Size' : 'Maximize Panel Size',
              onTap: () {
                ide.panelMaximized = !ide.panelMaximized;
                ide.touch();
              },
            ),
            IconBtn(icon: Icons.close_rounded, tooltip: 'Hide Panel (Ctrl+J)', onTap: ide.togglePanel),
            const SizedBox(width: 6),
          ]),
        ),
        Container(height: 1, color: t.border),
        Expanded(
          child: switch (ide.panelTab) {
            PanelTab.problems => const _ProblemsView(),
            PanelTab.output => const _OutputView(),
            PanelTab.terminal => const _TerminalsView(),
          },
        ),
      ]),
    );
  }

  List<Widget> _terminalActions(BuildContext context, Ide ide) => [
        IconBtn(icon: Icons.add_rounded, tooltip: 'New Terminal (Ctrl+Shift+`)', onTap: ide.newTerminal),
        IconBtn(
          icon: Icons.expand_more_rounded,
          tooltip: 'Launch Profile…',
          onTap: () {
            final RenderBox box = context.findRenderObject()! as RenderBox;
            showContextMenu(context, box.localToGlobal(Offset(box.size.width - 300, 34)), [
              for (final ShellProfile pr in ide.terminals.profiles) MenuEntry(pr.name, icon: Icons.terminal_rounded, onTap: () => ide.newTerminal(profile: pr)),
              const MenuEntry.divider(),
              MenuEntry('Select Default Profile', onTap: ide.showDefaultShellPicker),
            ]);
          },
        ),
        IconBtn(icon: Icons.cleaning_services_outlined, size: 15, tooltip: 'Clear Terminal', onTap: ide.terminals.clearActive),
        IconBtn(
          icon: Icons.delete_outline_rounded,
          tooltip: 'Kill Terminal',
          onTap: ide.terminals.active == null ? null : () => ide.terminals.close(ide.terminals.active!),
        ),
      ];

  List<Widget> _outputActions(BuildContext context, Ide ide) {
    final IdeTheme t = context.t;
    final OutputService out = ide.output;
    return [
      Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: t.inputBg, borderRadius: BorderRadius.circular(6), border: Border.all(color: t.border)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: out.channelNames.contains(out.selected) ? out.selected : out.channelNames.first,
            isDense: true,
            dropdownColor: t.surface,
            style: uiText(t, size: 12),
            items: [for (final String c in out.channelNames) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) {
              if (v != null) out.select(v);
            },
          ),
        ),
      ),
      IconBtn(icon: Icons.cleaning_services_outlined, size: 15, tooltip: 'Clear Output', onTap: () => out.clear(out.selected)),
    ];
  }
}

class _PanelTab extends StatelessWidget {
  const _PanelTab({required this.label, required this.selected, required this.onTap, this.badge});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return HoverBox(
      onTap: onTap,
      radius: 6,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label.toUpperCase(), style: uiText(t, size: 11.5, weight: FontWeight.w600, color: selected ? t.text : t.textMuted).copyWith(letterSpacing: 0.6)),
          if (badge != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(8)),
              child: Text(badge!, style: uiText(t, size: 10.5, color: t.accent, weight: FontWeight.w700)),
            ),
          ],
        ]),
        const SizedBox(height: 3),
        AnimatedContainer(duration: const Duration(milliseconds: 150), height: 2, width: selected ? 24 : 0, decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(2))),
      ]),
    );
  }
}

class _ProblemsView extends StatelessWidget {
  const _ProblemsView();

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Workspace ws = context.watch<Workspace>();
    final List<MapEntry<String, List<Diagnostic>>> files = ws.diagnostics.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    if (files.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.verified_outlined, size: 30, color: t.success),
          const SizedBox(height: 8),
          Text('No problems have been detected in the workspace.', style: uiText(t, color: t.textMuted)),
          const SizedBox(height: 4),
          Text('Diagnostics come from language servers (e.g. pyright, clangd, gopls).', style: uiText(t, size: 12, color: t.textFaint)),
        ]),
      );
    }
    return ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: [
      for (final MapEntry<String, List<Diagnostic>> f in files) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Row(children: [
            FileBadge(path: f.key, size: 14),
            const SizedBox(width: 6),
            Text(p.basename(f.key), style: uiText(t, size: 12.5, weight: FontWeight.w600)),
            const SizedBox(width: 6),
            Text(ws.relative(p.dirname(f.key)), style: uiText(t, size: 11, color: t.textFaint)),
            const SizedBox(width: 6),
            Text('${f.value.length}', style: uiText(t, size: 11, color: t.textMuted)),
          ]),
        ),
        for (final Diagnostic d in f.value)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: HoverBox(
              radius: 6,
              onTap: () => ws.openFile(f.key, line: d.line + 1, column: d.column + 1),
              padding: const EdgeInsets.fromLTRB(26, 3, 8, 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  switch (d.severity) {
                    DiagnosticSeverity.error => Icons.error_rounded,
                    DiagnosticSeverity.warning => Icons.warning_rounded,
                    _ => Icons.info_rounded,
                  },
                  size: 15,
                  color: switch (d.severity) {
                    DiagnosticSeverity.error => t.error,
                    DiagnosticSeverity.warning => t.warning,
                    _ => t.info,
                  },
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(d.message, style: uiText(t, size: 12.5))),
                Text('${d.source ?? ''}  [${d.line + 1}, ${d.column + 1}]', style: uiText(t, size: 11, color: t.textFaint)),
              ]),
            ),
          ),
      ],
    ]);
  }
}

class _OutputView extends StatefulWidget {
  const _OutputView();

  @override
  State<_OutputView> createState() => _OutputViewState();
}

class _OutputViewState extends State<_OutputView> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final OutputService out = context.watch<OutputService>();
    final List<String> lines = out.lines(out.selected);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
    return SelectionArea(
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(10),
        itemCount: lines.length,
        itemBuilder: (context, i) => Text(lines[i], style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12.5, color: t.textMuted, height: 1.5)),
      ),
    );
  }
}

class _TerminalsView extends StatelessWidget {
  const _TerminalsView();

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final TerminalService ts = context.watch<TerminalService>();
    final Ide ide = context.read<Ide>();
    if (ts.sessions.isEmpty) {
      return Center(
        child: AccentButton(label: 'New Terminal', icon: Icons.terminal_rounded, onTap: ide.newTerminal),
      );
    }
    final TerminalSession active = ts.active ?? ts.sessions.first;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: TerminalPane(key: ValueKey(active.id), session: active)),
      if (ts.sessions.length > 1)
        Container(
          width: 180,
          decoration: BoxDecoration(border: Border(left: BorderSide(color: t.border))),
          child: ListView(padding: const EdgeInsets.all(4), children: [
            for (int i = 0; i < ts.sessions.length; i++) _SessionRow(session: ts.sessions[i], index: i, active: ts.sessions[i] == active),
          ]),
        ),
    ]);
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.index, required this.active});

  final TerminalSession session;
  final int index;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final TerminalService ts = context.read<TerminalService>();
    return HoverBox(
      selected: active,
      radius: 6,
      onTap: () => ts.setActive(index),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(children: [
        SizedBox(width: 20, child: Text(session.profile.icon, style: uiText(t, size: 10.5, color: session.exited ? t.textFaint : t.accent, weight: FontWeight.w700))),
        Expanded(child: Text(session.title, style: uiText(t, size: 12, color: session.exited ? t.textFaint : t.text), overflow: TextOverflow.ellipsis)),
        HoverBox(onTap: () => ts.close(session), radius: 4, child: Icon(Icons.close_rounded, size: 13, color: t.textMuted)),
      ]),
    );
  }
}

class TerminalPane extends StatefulWidget {
  const TerminalPane({super.key, required this.session});

  final TerminalSession session;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _copyOrPaste() async {
    final TerminalSession s = widget.session;
    final BufferRange? sel = s.controller.selection;
    if (sel != null) {
      await Clipboard.setData(ClipboardData(text: s.terminal.buffer.getText(sel)));
      s.controller.clearSelection();
    } else {
      final ClipboardData? data = await Clipboard.getData('text/plain');
      if (data?.text != null) s.terminal.paste(data!.text!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Ide ide = context.watch<Ide>();
    context.watch<FontManager>();
    final IdeTheme t = ide.effectiveTheme;
    final String font = ide.fonts.isLoaded(ide.settings.terminalFont) ? ide.settings.terminalFont : 'JetBrains Mono';
    return Container(
      color: t.editorBg,
      padding: const EdgeInsets.only(left: 10, top: 6),
      child: TerminalView(
        widget.session.terminal,
        controller: widget.session.controller,
        focusNode: _focus,
        autofocus: true,
        theme: t.terminal,
        cursorType: TerminalCursorType.verticalBar,
        textStyle: TerminalStyle(fontSize: ide.settings.terminalFontSize, fontFamily: font, fontFamilyFallback: FontManager.fallback, height: 1.25),
        onSecondaryTapDown: (_, _) => _copyOrPaste(),
        onKeyEvent: (node, e) {
          if (ide.handleTerminalKey(e)) return KeyEventResult.handled;
          final HardwareKeyboard hk = HardwareKeyboard.instance;
          if (e is KeyDownEvent && hk.isControlPressed && !hk.isShiftPressed && e.logicalKey == LogicalKeyboardKey.keyC && widget.session.controller.selection != null) {
            _copyOrPaste();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
      ),
    );
  }
}
