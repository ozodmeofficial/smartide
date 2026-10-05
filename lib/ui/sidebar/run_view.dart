import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/ide.dart';
import '../../core/languages.dart';
import '../../core/toolchain.dart';
import '../../services/live_server.dart';
import '../../services/terminal_service.dart';
import '../../theme/ide_theme.dart';
import '../../workspace/editor_document.dart';
import '../widgets.dart';

/// "Run & Tools" view: run the current file, build, Live Server and a
/// dashboard of the developer tools found on this machine.
class RunView extends StatelessWidget {
  const RunView({super.key});

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Ide ide = context.watch<Ide>();
    final Toolchain tc = context.watch<Toolchain>();
    final LiveServer live = context.watch<LiveServer>();
    final TerminalService terms = context.watch<TerminalService>();
    final EditorDocument? doc = ide.workspace.activeDocument;
    final LanguageDef? lang = doc?.language;
    final bool running = terms.sessions.any((s) => s.isTask && !s.exited);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const PaneHeader(title: 'Run and Tools'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AccentButton(
              label: doc == null ? 'Run File' : 'Run ${doc.title}',
              icon: Icons.play_arrow_rounded,
              onTap: doc == null ? null : ide.runActiveFile,
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: AccentButton(label: 'Build', subtle: true, icon: Icons.construction_rounded, onTap: ide.runBuildTask)),
              const SizedBox(width: 6),
              Expanded(child: AccentButton(label: 'Stop', subtle: true, icon: Icons.stop_rounded, onTap: running ? ide.stopRun : null)),
            ]),
            const SizedBox(height: 8),
            if (lang != null)
              Text(
                lang.run != null
                    ? 'F5 runs ${lang.name} files in the integrated terminal.'
                    : (lang.id == 'html' ? 'F5 opens HTML files with Live Server.' : 'No runner for ${lang.name} files.'),
                style: uiText(t, size: 12, color: t.textMuted),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        const PaneHeader(title: 'Live Server'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: t.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: live.running ? t.success : t.textFaint, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(live.running ? 'Running on port ${live.port}' : 'Stopped', style: uiText(t, size: 13, weight: FontWeight.w500))),
              ]),
              if (live.running) ...[
                const SizedBox(height: 6),
                HoverBox(
                  onTap: () => LiveServer.openInBrowser(live.url),
                  radius: 4,
                  child: Text(live.url, style: uiText(t, size: 12, color: t.accent).copyWith(decoration: TextDecoration.underline)),
                ),
              ],
              const SizedBox(height: 10),
              AccentButton(label: live.running ? 'Stop Server' : 'Go Live', subtle: live.running, icon: Icons.podcasts_rounded, dense: true, onTap: () => ide.toggleLiveServer()),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        PaneHeader(title: 'Installed Tools', actions: [
          if (tc.scanning)
            Padding(padding: const EdgeInsets.all(6), child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: t.accent)))
          else
            IconBtn(icon: Icons.refresh_rounded, size: 15, tooltip: 'Re-scan', onTap: () => ide.commands.execute('smartide.detectTools')),
        ]),
        for (final ToolInfo tool in tc.tools)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: HoverBox(
              radius: 6,
              tooltip: tool.available ? 'Found: ${tool.resolved}' : 'Install: ${tool.installHint}',
              onTap: tool.available
                  ? null
                  : () {
                      ide.showPanel(PanelTab.terminal);
                      ide.terminals.sendToActive(tool.installHint.split('  ').first, execute: false);
                    },
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(children: [
                Icon(
                  !tool.checked ? Icons.hourglass_empty_rounded : (tool.available ? Icons.check_circle_rounded : Icons.download_for_offline_outlined),
                  size: 15,
                  color: tool.available ? t.success : t.textFaint,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(tool.name, style: uiText(t, size: 12.5, color: tool.available ? t.text : t.textMuted))),
                Text(tool.available ? (tool.version ?? '') : 'install', style: uiText(t, size: 11, color: tool.available ? t.textFaint : t.accent)),
              ]),
            ),
          ),
        const SizedBox(height: 14),
        PaneHeader(title: 'Terminal Profiles', actions: [
          IconBtn(icon: Icons.add_rounded, size: 15, tooltip: 'New Terminal', onTap: ide.newTerminal),
        ]),
        for (final ShellProfile pr in terms.profiles)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: HoverBox(
              radius: 6,
              onTap: () => ide.newTerminal(profile: pr),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(children: [
                SizedBox(width: 22, child: Text(pr.icon, style: uiText(t, size: 11, color: t.accent, weight: FontWeight.w700))),
                Expanded(child: Text(pr.name, style: uiText(t, size: 12.5))),
                if (pr.id == terms.defaultProfile.id) Text('default', style: uiText(t, size: 11, color: t.textFaint)),
              ]),
            ),
          ),
      ],
    );
  }
}
