import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';

import '../app/ide.dart';
import '../services/git_service.dart';
import '../services/live_server.dart';
import '../services/lsp_service.dart';
import '../theme/ide_theme.dart';
import '../workspace/editor_document.dart';
import '../workspace/workspace.dart';
import 'widgets.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Ide ide = context.watch<Ide>();
    final Workspace ws = context.watch<Workspace>();
    final GitService git = context.watch<GitService>();
    final LiveServer live = context.watch<LiveServer>();
    final LspService lsp = context.watch<LspService>();
    final EditorDocument? doc = ws.activeDocument;
    final String lspStatus = lsp.statusFor(doc);
    return Container(
      height: 26,
      color: t.chrome,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(children: [
        if (git.isRepo)
          _Item(
            icon: Icons.call_split_rounded,
            label: '${git.branch}${git.changeCount > 0 ? '*' : ''}',
            tooltip: 'Checkout branch',
            onTap: ide.showBranchPicker,
          ),
        if (git.isRepo && git.upstream != null)
          _Item(icon: Icons.sync_rounded, label: '${git.behind}↓ ${git.ahead}↑', tooltip: 'Synchronize Changes', onTap: () => ide.commands.execute('git.sync')),
        _Item(
          icon: Icons.error_outline_rounded,
          label: '${ws.errorCount}',
          trailingIcon: Icons.warning_amber_rounded,
          trailingLabel: '${ws.warningCount}',
          tooltip: 'Problems (Ctrl+Shift+M)',
          onTap: () => ide.showPanel(PanelTab.problems, toggle: true),
        ),
        if (lspStatus.isNotEmpty)
          _Item(icon: Icons.bolt_rounded, label: lspStatus, tooltip: 'Language server', onTap: () {
            ide.output.select(ide.output.channelNames.lastWhere((c) => c.startsWith('Language'), orElse: () => 'SmartIDE'));
            ide.showPanel(PanelTab.output);
          }),
        const Spacer(),
        if (doc != null) ...[
          SafeListenableBuilder(
            listenable: doc.controller,
            builder: (context) {
              final CodeLineSelection s = doc.controller.selection;
              final int selLen = s.isCollapsed ? 0 : doc.controller.selectedText.length;
              return _Item(label: 'Ln ${s.extentIndex + 1}, Col ${s.extentOffset + 1}${selLen > 0 ? ' ($selLen selected)' : ''}', tooltip: 'Go to Line (Ctrl+G)', onTap: ide.showGotoLine);
            },
          ),
          _Item(label: ide.settings.insertSpaces ? 'Spaces: ${ide.settings.tabSize}' : 'Tab Size: ${ide.settings.tabSize}', tooltip: 'Indentation', onTap: () => ide.workspace.openSpecial(TabKind.settings)),
          _Item(label: 'UTF-8', tooltip: 'Encoding'),
          _Item(label: doc.lineBreakLabel, tooltip: 'End of Line Sequence'),
          _Item(label: doc.language.name, tooltip: 'Select Language Mode', onTap: ide.showLanguagePicker),
        ],
        if (ide.extensions.isEnabled('smartide.liveserver'))
          _Item(
            icon: live.running ? Icons.podcasts_rounded : Icons.wifi_tethering_rounded,
            label: live.running ? 'Port: ${live.port}' : 'Go Live',
            tooltip: live.running ? 'Click to stop Live Server' : 'Click to run Live Server',
            highlight: live.running,
            onTap: () => ide.toggleLiveServer(),
          ),
        _Item(icon: Icons.notifications_none_rounded, label: '', tooltip: 'Notifications', onTap: () {
          ide.output.select('SmartIDE');
          ide.showPanel(PanelTab.output);
        }),
      ]),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({this.icon, required this.label, this.tooltip, this.onTap, this.trailingIcon, this.trailingLabel, this.highlight = false});

  final IconData? icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onTap;
  final IconData? trailingIcon;
  final String? trailingLabel;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Color c = highlight ? t.accent : t.textMuted;
    return HoverBox(
      onTap: onTap,
      tooltip: tooltip,
      radius: 5,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) Icon(icon, size: 13.5, color: c),
        if (icon != null && label.isNotEmpty) const SizedBox(width: 4),
        if (label.isNotEmpty) Text(label, style: uiText(t, size: 11.5, color: c, weight: highlight ? FontWeight.w600 : null)),
        if (trailingIcon != null) ...[
          const SizedBox(width: 8),
          Icon(trailingIcon, size: 13.5, color: c),
          const SizedBox(width: 4),
          Text(trailingLabel ?? '', style: uiText(t, size: 11.5, color: c)),
        ],
      ]),
    );
  }
}
