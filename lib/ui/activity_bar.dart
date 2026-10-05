import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/ide.dart';
import '../services/git_service.dart';
import '../theme/ide_theme.dart';
import '../workspace/editor_document.dart';
import 'widgets.dart';

class ActivityBar extends StatelessWidget {
  const ActivityBar({super.key});

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Ide ide = context.watch<Ide>();
    final GitService git = context.watch<GitService>();
    Widget item(SideView v, IconData icon, IconData activeIcon, String tip, {int badge = 0}) {
      final bool sel = ide.sidebarVisible && ide.sideView == v;
      return _ActivityItem(icon: sel ? activeIcon : icon, tooltip: tip, selected: sel, badge: badge, onTap: () => ide.showView(v, toggle: true));
    }

    return Container(
      width: 52,
      color: t.chrome,
      child: Column(children: [
        const SizedBox(height: 4),
        item(SideView.explorer, Icons.folder_copy_outlined, Icons.folder_copy_rounded, 'Explorer (Ctrl+Shift+E)'),
        item(SideView.search, Icons.search_rounded, Icons.manage_search_rounded, 'Search (Ctrl+Shift+F)'),
        item(SideView.scm, Icons.account_tree_outlined, Icons.account_tree_rounded, 'Source Control (Ctrl+Shift+G)', badge: git.isRepo ? git.changeCount : 0),
        item(SideView.run, Icons.play_circle_outline_rounded, Icons.play_circle_rounded, 'Run and Tools (Ctrl+Shift+D)'),
        item(SideView.extensions, Icons.extension_outlined, Icons.extension_rounded, 'Extensions (Ctrl+Shift+X)'),
        const Spacer(),
        if (ide.extensions.isEnabled('smartide.assistant'))
          _ActivityItem(icon: Icons.auto_awesome_outlined, tooltip: 'SmartIDE Assistant (Ctrl+Alt+I)', selected: ide.assistantVisible, onTap: ide.toggleAssistant),
        _ActivityItem(icon: Icons.palette_outlined, tooltip: 'Color Theme (Ctrl+K Ctrl+T)', onTap: ide.showThemePicker),
        _ActivityItem(
          icon: Icons.settings_outlined,
          tooltip: 'Manage',
          onTap: () {
            final RenderBox box = context.findRenderObject()! as RenderBox;
            showContextMenu(context, box.localToGlobal(Offset(56, box.size.height - 260)), [
              MenuEntry('Command Palette…', shortcut: 'Ctrl+Shift+P', onTap: ide.showCommandPalette),
              const MenuEntry.divider(),
              MenuEntry('Settings', shortcut: 'Ctrl+,', onTap: () => ide.workspace.openSpecial(TabKind.settings)),
              MenuEntry('Extensions', shortcut: 'Ctrl+Shift+X', onTap: () => ide.showView(SideView.extensions)),
              MenuEntry('Keyboard Shortcuts', onTap: () => ide.workspace.openSpecial(TabKind.keybindings)),
              const MenuEntry.divider(),
              MenuEntry('Color Theme', onTap: ide.showThemePicker),
              MenuEntry('Editor Font', onTap: ide.showFontPicker),
              MenuEntry('Toggle Light / Dark', onTap: () => ide.commands.execute('workbench.action.toggleLightDark')),
            ]);
          },
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _ActivityItem extends StatefulWidget {
  const _ActivityItem({required this.icon, required this.tooltip, required this.onTap, this.selected = false, this.badge = 0});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;
  final int badge;

  @override
  State<_ActivityItem> createState() => _ActivityItemState();
}

class _ActivityItemState extends State<_ActivityItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      verticalOffset: 0,
      margin: const EdgeInsets.only(left: 56),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: SizedBox(
            width: 52,
            height: 46,
            child: Stack(alignment: Alignment.center, children: [
              Positioned(
                left: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 3,
                  height: widget.selected ? 22 : 0,
                  decoration: BoxDecoration(color: t.accent, borderRadius: const BorderRadius.horizontal(right: Radius.circular(3))),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: widget.selected ? t.accentSoft : (_hover ? t.hover : Colors.transparent),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, size: 21, color: widget.selected ? t.accent : (_hover ? t.text : t.textMuted)),
              ),
              if (widget.badge > 0)
                Positioned(
                  right: 7,
                  bottom: 6,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(8), border: Border.all(color: t.chrome, width: 1.5)),
                    child: Text(widget.badge > 99 ? '99+' : '${widget.badge}', textAlign: TextAlign.center, style: uiText(t, size: 9.5, color: t.onAccent, weight: FontWeight.w700)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
