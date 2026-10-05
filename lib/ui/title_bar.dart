import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../app/ide.dart';
import '../core/commands.dart';
import '../theme/ide_theme.dart';
import '../workspace/workspace.dart';
import 'logo.dart';
import 'widgets.dart';

class TitleBar extends StatefulWidget {
  const TitleBar({super.key});

  @override
  State<TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<TitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  List<MenuEntry> _entries(Ide ide, List<(String, String)> items) {
    final CommandRegistry c = ide.commands;
    return [
      for (final (String label, String id) in items)
        if (id == '-')
          const MenuEntry.divider()
        else
          MenuEntry(label, shortcut: c.shortcutFor(id), enabled: c[id]?.isEnabled ?? false, onTap: () => c.execute(id)),
    ];
  }

  Map<String, List<(String, String)>> get _menus => const {
        'File': [
          ('New Text File', 'workbench.action.files.newUntitledFile'),
          ('New File…', 'workbench.action.files.newFile'),
          ('New Window', 'workbench.action.newWindow'),
          ('-', '-'),
          ('Open File…', 'workbench.action.files.openFile'),
          ('Open Folder…', 'workbench.action.files.openFolder'),
          ('-', '-'),
          ('Save', 'workbench.action.files.save'),
          ('Save As…', 'workbench.action.files.saveAs'),
          ('Save All', 'workbench.action.files.saveAll'),
          ('Revert File', 'workbench.action.files.revert'),
          ('-', '-'),
          ('Preferences: Settings', 'workbench.action.openSettings'),
          ('Preferences: Keyboard Shortcuts', 'workbench.action.openGlobalKeybindings'),
          ('Preferences: Color Theme', 'workbench.action.selectTheme'),
          ('-', '-'),
          ('Close Editor', 'workbench.action.closeActiveEditor'),
          ('Close Folder', 'workbench.action.closeFolder'),
          ('Exit', 'workbench.action.quit'),
        ],
        'Edit': [
          ('Find in Files', 'workbench.view.search'),
          ('Format Document', 'editor.action.formatDocument'),
          ('Trigger Suggest', 'editor.action.triggerSuggest'),
          ('-', '-'),
          ('Copy Line Down', 'editor.action.copyLinesDownAction'),
          ('Copy Line Up', 'editor.action.copyLinesUpAction'),
          ('Insert Line Below', 'editor.action.insertLineAfter'),
          ('Insert Line Above', 'editor.action.insertLineBefore'),
          ('-', '-'),
          ('Change Language Mode', 'editor.action.changeLanguage'),
        ],
        'Selection': [
          ('Select Next Occurrence', 'editor.action.addSelectionToNextFindMatch'),
          ('Go to Bracket', 'editor.action.jumpToBracket'),
          ('Indent Line', 'editor.action.indentLines'),
          ('Outdent Line', 'editor.action.outdentLines'),
        ],
        'View': [
          ('Command Palette…', 'workbench.action.showCommands'),
          ('-', '-'),
          ('Explorer', 'workbench.view.explorer'),
          ('Search', 'workbench.view.search'),
          ('Source Control', 'workbench.view.scm'),
          ('Run', 'workbench.view.debug'),
          ('Extensions', 'workbench.view.extensions'),
          ('-', '-'),
          ('Problems', 'workbench.actions.view.problems'),
          ('Output', 'workbench.action.output.toggleOutput'),
          ('Terminal', 'workbench.action.terminal.toggleTerminal'),
          ('Assistant', 'workbench.action.toggleAssistant'),
          ('-', '-'),
          ('Toggle Primary Side Bar', 'workbench.action.toggleSidebarVisibility'),
          ('Toggle Panel', 'workbench.action.togglePanel'),
          ('Split Editor', 'workbench.action.splitEditor'),
          ('Zen Mode', 'workbench.action.toggleZenMode'),
          ('Full Screen', 'workbench.action.toggleFullScreen'),
          ('Word Wrap', 'editor.action.wordWrap'),
          ('-', '-'),
          ('Zoom In', 'workbench.action.zoomIn'),
          ('Zoom Out', 'workbench.action.zoomOut'),
          ('Reset Zoom', 'workbench.action.zoomReset'),
        ],
        'Go': [
          ('Go to File…', 'workbench.action.quickOpen'),
          ('Go to Line…', 'workbench.action.gotoLine'),
          ('Go to Definition', 'editor.action.revealDefinition'),
          ('Next Problem', 'editor.action.marker.next'),
          ('Previous Problem', 'editor.action.marker.prev'),
          ('-', '-'),
          ('Next Editor', 'workbench.action.nextEditor'),
          ('Previous Editor', 'workbench.action.previousEditor'),
        ],
        'Run': [
          ('Run Current File', 'workbench.action.debug.start'),
          ('Stop', 'workbench.action.debug.stop'),
          ('Run Build Task', 'workbench.action.tasks.build'),
          ('-', '-'),
          ('Open with Live Server / Stop', 'liveServer.toggle'),
        ],
        'Terminal': [
          ('New Terminal', 'workbench.action.terminal.new'),
          ('New Terminal With Profile…', 'workbench.action.terminal.newWithProfile'),
          ('Select Default Profile', 'workbench.action.terminal.selectDefaultShell'),
          ('-', '-'),
          ('Clear Terminal', 'workbench.action.terminal.clear'),
          ('Kill Terminal', 'workbench.action.terminal.kill'),
        ],
        'Help': [
          ('Welcome', 'workbench.action.openWelcome'),
          ('Show All Commands', 'workbench.action.showCommands'),
          ('Keyboard Shortcuts', 'workbench.action.openGlobalKeybindings'),
          ('-', '-'),
          ('Re-scan Installed Tools', 'smartide.detectTools'),
          ('Restart Language Servers', 'smartide.restartLanguageServers'),
        ],
      };

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Ide ide = context.watch<Ide>();
    final Workspace ws = context.watch<Workspace>();
    return Container(
      height: 40,
      color: t.chrome,
      child: Row(children: [
        const SizedBox(width: 12),
        const SmartIdeLogo(size: 20),
        const SizedBox(width: 8),
        for (final MapEntry<String, List<(String, String)>> m in _menus.entries)
          Builder(builder: (ctx) {
            return HoverBox(
              radius: 6,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              onTap: () {
                final RenderBox box = ctx.findRenderObject()! as RenderBox;
                showContextMenu(ctx, box.localToGlobal(Offset(0, box.size.height + 4)), _entries(ide, m.value));
              },
              child: Text(m.key, style: uiText(t, size: 12.5, color: t.textMuted)),
            );
          }),
        Expanded(
          child: DragToMoveArea(
            child: GestureDetector(
              onDoubleTap: () async => _maximized ? windowManager.unmaximize() : windowManager.maximize(),
              child: Container(
                color: Colors.transparent,
                alignment: Alignment.center,
                child: _CommandCenter(label: ws.hasFolder ? ws.folderName : 'SmartIDE', onTap: ide.showQuickOpen, chord: ide.commands.pendingChordFirst?.label),
              ),
            ),
          ),
        ),
        IconBtn(icon: ide.sidebarVisible ? Icons.view_sidebar_rounded : Icons.view_sidebar_outlined, tooltip: 'Toggle Primary Side Bar (Ctrl+B)', onTap: ide.toggleSidebar, active: ide.sidebarVisible),
        IconBtn(icon: Icons.call_to_action_outlined, tooltip: 'Toggle Panel (Ctrl+J)', onTap: ide.togglePanel, active: ide.panelVisible),
        if (ide.extensions.isEnabled('smartide.assistant'))
          IconBtn(icon: Icons.auto_awesome_rounded, tooltip: 'Assistant (Ctrl+Alt+I)', onTap: ide.toggleAssistant, active: ide.assistantVisible),
        const SizedBox(width: 8),
        _WinButton(icon: Icons.remove_rounded, onTap: windowManager.minimize),
        _WinButton(icon: _maximized ? Icons.filter_none_rounded : Icons.crop_square_rounded, iconSize: _maximized ? 13 : 15, onTap: () => _maximized ? windowManager.unmaximize() : windowManager.maximize()),
        _WinButton(icon: Icons.close_rounded, close: true, onTap: windowManager.close),
      ]),
    );
  }
}

class _CommandCenter extends StatelessWidget {
  const _CommandCenter({required this.label, required this.onTap, this.chord});

  final String label;
  final VoidCallback onTap;
  final String? chord;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480, minWidth: 220),
      child: HoverBox(
        onTap: onTap,
        radius: 8,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: t.isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.border),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.search_rounded, size: 15, color: t.textMuted),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                chord != null ? '($chord) was pressed. Waiting for second key of chord…' : label,
                overflow: TextOverflow.ellipsis,
                style: uiText(t, size: 12.5, color: t.textMuted),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _WinButton extends StatefulWidget {
  const _WinButton({required this.icon, required this.onTap, this.close = false, this.iconSize = 16});

  final IconData icon;
  final VoidCallback onTap;
  final bool close;
  final double iconSize;

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: Platform.isWindows ? 46 : 40,
          height: 40,
          color: _hover ? (widget.close ? const Color(0xFFE81123) : t.hover) : Colors.transparent,
          child: Icon(widget.icon, size: widget.iconSize, color: _hover && widget.close ? Colors.white : t.textMuted),
        ),
      ),
    );
  }
}
