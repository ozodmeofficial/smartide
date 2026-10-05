import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../app/ide.dart';
import '../../core/templates.dart';
import '../../core/toolchain.dart';
import '../../theme/ide_theme.dart';
import '../dialogs.dart';
import '../logo.dart';
import '../widgets.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  String _greeting() {
    final int h = DateTime.now().hour;
    if (h < 5) return 'Burning the midnight oil';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Ide ide = context.watch<Ide>();
    return LayoutBuilder(builder: (context, box) {
      final bool wide = box.maxWidth > 980;
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: wide ? 64 : 28, vertical: 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const SmartIdeLogo(size: 54),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_greeting()}.', style: serifText(t, size: 38)),
                      const SizedBox(height: 4),
                      Text('What will you build today?', style: uiText(t, size: 16, color: t.textMuted)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 32),
                _QuickBar(ide: ide),
                const SizedBox(height: 36),
                if (wide)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 5, child: Column(children: [_Templates(ide: ide), const SizedBox(height: 28), _Recent(ide: ide)])),
                    const SizedBox(width: 32),
                    Expanded(flex: 4, child: Column(children: [_Machine(ide: ide), const SizedBox(height: 28), _Shortcuts(ide: ide), const SizedBox(height: 28), _Themes(ide: ide)])),
                  ])
                else ...[
                  _Templates(ide: ide),
                  const SizedBox(height: 28),
                  _Recent(ide: ide),
                  const SizedBox(height: 28),
                  _Machine(ide: ide),
                  const SizedBox(height: 28),
                  _Shortcuts(ide: ide),
                  const SizedBox(height: 28),
                  _Themes(ide: ide),
                ],
                const SizedBox(height: 40),
                Center(child: Text('SmartIDE 1.0 · made with care', style: uiText(t, size: 12, color: t.textFaint))),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(title, style: serifText(t, size: 20)),
        const Spacer(),
        ?trailing,
      ]),
      const SizedBox(height: 12),
      child,
    ]);
  }
}

class _QuickBar extends StatelessWidget {
  const _QuickBar({required this.ide});

  final Ide ide;

  @override
  Widget build(BuildContext context) {
    final List<(IconData, String, String, VoidCallback)> actions = [
      (Icons.note_add_outlined, 'New File', 'Ctrl+N', () => ide.workspace.newUntitled()),
      (Icons.file_open_outlined, 'Open File', 'Ctrl+O', ide.openFileDialog),
      (Icons.folder_open_outlined, 'Open Folder', 'Ctrl+K Ctrl+O', () => ide.openFolder()),
      (Icons.cloud_download_outlined, 'Clone Repository', 'git clone', () => _clone(context)),
      (Icons.terminal_rounded, 'New Terminal', 'Ctrl+Shift+`', ide.newTerminal),
    ];
    return Wrap(spacing: 12, runSpacing: 12, children: [
      for (final (IconData icon, String label, String hint, VoidCallback onTap) in actions) _ActionCard(icon: icon, label: label, hint: hint, onTap: onTap),
    ]);
  }

  Future<void> _clone(BuildContext context) async {
    final String? url = await showInputDialog(context, title: 'Clone Git Repository', hint: 'https://github.com/user/repo.git', confirm: 'Choose Folder…');
    if (url == null || url.trim().isEmpty) return;
    final String? parent = await getDirectoryPath(confirmButtonText: 'Clone Here');
    if (parent == null) return;
    String name = p.basenameWithoutExtension(Uri.tryParse(url.trim())?.path ?? 'repo');
    if (name.isEmpty) name = 'repo';
    final String target = p.join(parent, name);
    ide.terminals.cwd = parent;
    ide.terminals.runTask('⤓ Clone', 'git clone "${url.trim()}" "$target"', workingDirectory: parent, onExit: (code) {
      if (code == 0) ide.openFolder(target);
    });
    ide.showPanel(PanelTab.terminal);
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.label, required this.hint, required this.onTap});

  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return HoverBox(
      onTap: onTap,
      radius: 12,
      child: Container(
        width: 176,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: t.border)),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: t.accentSoft, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 18, color: t.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: uiText(t, size: 13.5, weight: FontWeight.w600)),
              Text(hint, style: uiText(t, size: 11, color: t.textFaint), overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Templates extends StatelessWidget {
  const _Templates({required this.ide});

  final Ide ide;

  Future<void> _create(BuildContext context, ProjectTemplate tpl) async {
    final String? name = await showInputDialog(context, title: 'New ${tpl.name} project', initial: 'my-${tpl.id}-app', hint: 'Project name', confirm: 'Choose Location…');
    if (name == null || name.trim().isEmpty) return;
    final String? parent = await getDirectoryPath(confirmButtonText: 'Create Here');
    if (parent == null) return;
    if (await Directory(p.join(parent, name.trim())).exists()) {
      ide.notifications.error('A folder named "${name.trim()}" already exists there.');
      return;
    }
    final String root = await tpl.create(parent, name.trim());
    await ide.openFolder(root);
    await ide.workspace.openFile(p.join(root, tpl.mainFile.replaceAll('{{name}}', name.trim())));
    ide.notifications.success('Project "${name.trim()}" created', detail: 'Press F5 to run it.');
  }

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return _Section(
      title: 'Start a new project',
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        for (final ProjectTemplate tpl in projectTemplates)
          HoverBox(
            onTap: () => _create(context, tpl),
            radius: 10,
            child: Container(
              width: 236,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: t.border)),
              child: Row(children: [
                LanguageBadge(badge: tpl.badge, color: tpl.color, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tpl.name, style: uiText(t, size: 13, weight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    Text(tpl.description, style: uiText(t, size: 11, color: t.textFaint), overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _Recent extends StatelessWidget {
  const _Recent({required this.ide});

  final Ide ide;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final List<String> recent = ide.settings.recentFolders;
    return _Section(
      title: 'Recent',
      trailing: recent.isEmpty ? null : HoverBox(
        onTap: () => ide.settings.update((s) => s.recentFolders = []),
        radius: 6,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text('Clear', style: uiText(t, size: 12, color: t.textMuted)),
      ),
      child: recent.isEmpty
          ? Text('Folders you open will appear here.', style: uiText(t, color: t.textFaint))
          : Column(children: [
              for (final String f in recent.take(8))
                HoverBox(
                  onTap: () => ide.openFolder(f),
                  radius: 8,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(children: [
                    Icon(Icons.folder_rounded, size: 18, color: t.accent.withValues(alpha: 0.85)),
                    const SizedBox(width: 10),
                    Text(p.basename(f), style: uiText(t, size: 13.5, weight: FontWeight.w500)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(p.dirname(f), style: uiText(t, size: 12, color: t.textFaint), overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ]),
    );
  }
}

class _Machine extends StatelessWidget {
  const _Machine({required this.ide});

  final Ide ide;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Toolchain tc = context.watch<Toolchain>();
    final List<ToolInfo> shown = tc.tools.where((x) => x.id != 'cargo' && x.id != 'bash').toList();
    return _Section(
      title: 'Your machine',
      trailing: tc.scanning
          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: t.accent))
          : IconBtn(icon: Icons.refresh_rounded, tooltip: 'Re-scan tools', onTap: () {
              Toolchain.clearCache();
              tc.scan();
            }),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: t.border)),
        child: Wrap(children: [
          for (final ToolInfo tool in shown)
            Tooltip(
              message: tool.available ? '${tool.resolved} ${tool.version ?? ''}' : 'Not found — ${tool.installHint}',
              child: Container(
                width: 160,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Row(children: [
                  Icon(
                    !tool.checked ? Icons.more_horiz_rounded : (tool.available ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded),
                    size: 15,
                    color: !tool.checked ? t.textFaint : (tool.available ? t.success : t.textFaint),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tool.name,
                      overflow: TextOverflow.ellipsis,
                      style: uiText(t, size: 12.5, color: tool.available ? t.text : t.textFaint),
                    ),
                  ),
                  if (tool.available && tool.version != null)
                    Text(tool.version!.length > 8 ? tool.version!.substring(0, 8) : tool.version!, style: uiText(t, size: 11, color: t.textFaint)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.ide});

  final Ide ide;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final List<(String, String)> rows = [
      ('Command Palette', 'workbench.action.showCommands'),
      ('Quick Open', 'workbench.action.quickOpen'),
      ('Run File', 'workbench.action.debug.start'),
      ('Terminal', 'workbench.action.terminal.toggleTerminal'),
      ('Toggle Sidebar', 'workbench.action.toggleSidebarVisibility'),
      ('Settings', 'workbench.action.openSettings'),
    ];
    return _Section(
      title: 'Same shortcuts you know',
      trailing: HoverBox(
        onTap: () => ide.commands.execute('workbench.action.openGlobalKeybindings'),
        radius: 6,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text('All shortcuts →', style: uiText(t, size: 12, color: t.accent)),
      ),
      child: Column(children: [
        for (final (String label, String id) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            child: Row(children: [
              Expanded(child: Text(label, style: uiText(t, color: t.textMuted))),
              Kbd(ide.commands.shortcutFor(id) ?? ''),
            ]),
          ),
      ]),
    );
  }
}

class _Themes extends StatelessWidget {
  const _Themes({required this.ide});

  final Ide ide;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final List<IdeTheme> picks = ide.allThemes.where((x) => const ['claude-dark', 'claude-light', 'one-dark', 'dracula', 'tokyo-night', 'catppuccin-mocha', 'github-light', 'nord'].contains(x.id)).toList();
    return _Section(
      title: 'Make it yours',
      trailing: HoverBox(
        onTap: ide.showThemePicker,
        radius: 6,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text('${ide.allThemes.length} themes →', style: uiText(t, size: 12, color: t.accent)),
      ),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        for (final IdeTheme th in picks)
          Tooltip(
            message: th.name,
            child: HoverBox(
              onTap: () => ide.settings.update((s) => s.themeId = th.id),
              radius: 10,
              child: Container(
                width: 66,
                height: 46,
                decoration: BoxDecoration(
                  color: th.editorBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ide.theme.id == th.id ? t.accent : t.border, width: ide.theme.id == th.id ? 2 : 1),
                ),
                padding: const EdgeInsets.all(8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  Container(height: 4, width: 30, decoration: BoxDecoration(color: th.palette.keyword, borderRadius: BorderRadius.circular(2))),
                  Container(height: 4, width: 42, decoration: BoxDecoration(color: th.palette.string, borderRadius: BorderRadius.circular(2))),
                  Container(height: 4, width: 22, decoration: BoxDecoration(color: th.accent, borderRadius: BorderRadius.circular(2))),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
