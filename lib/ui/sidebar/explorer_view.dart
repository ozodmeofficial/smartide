import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../app/ide.dart';
import '../../core/languages.dart';
import '../../theme/ide_theme.dart';
import '../../workspace/editor_document.dart';
import '../../workspace/workspace.dart';
import '../dialogs.dart';
import '../widgets.dart';

class ExplorerView extends StatefulWidget {
  const ExplorerView({super.key});

  @override
  State<ExplorerView> createState() => _ExplorerViewState();
}

class _ExplorerViewState extends State<ExplorerView> {
  bool _openEditors = true;
  bool _folder = true;
  String? _selected;
  String? _clipboard;
  bool _cut = false;
  final FocusNode _treeFocus = FocusNode();

  @override
  void dispose() {
    _treeFocus.dispose();
    super.dispose();
  }

  List<(FileNode, int)> _flatten(FileNode root) {
    final List<(FileNode, int)> out = [];
    void walk(FileNode n, int depth) {
      for (final FileNode c in n.children ?? const <FileNode>[]) {
        out.add((c, depth));
        if (c.isDir && c.expanded) walk(c, depth + 1);
      }
    }

    walk(root, 0);
    return out;
  }

  String _targetDir(Workspace ws) {
    if (_selected == null) return ws.root!;
    return FileSystemEntity.isDirectorySync(_selected!) ? _selected! : p.dirname(_selected!);
  }

  Future<void> _newFile(Workspace ws, [String? dir]) async {
    final String target = dir ?? _targetDir(ws);
    final String? name = await showInputDialog(context, title: 'New File', hint: 'File name (you can use folder/name.ext)');
    if (name == null || name.trim().isEmpty) return;
    final String? path = await ws.createFile(target, name.trim());
    if (path == null && mounted) context.ide.notifications.error('A file or folder "${name.trim()}" already exists.');
    if (path != null) setState(() => _selected = path);
  }

  Future<void> _newFolder(Workspace ws, [String? dir]) async {
    final String target = dir ?? _targetDir(ws);
    final String? name = await showInputDialog(context, title: 'New Folder', hint: 'Folder name');
    if (name == null || name.trim().isEmpty) return;
    final String? path = await ws.createFolder(target, name.trim());
    if (path != null) {
      final FileNode? node = _find(ws.tree, target);
      if (node != null && !node.expanded) await ws.toggleNode(node);
    }
  }

  FileNode? _find(FileNode? n, String path) {
    if (n == null) return null;
    if (p.equals(n.path, path)) return n;
    for (final FileNode c in n.children ?? const <FileNode>[]) {
      final FileNode? r = _find(c, path);
      if (r != null) return r;
    }
    return null;
  }

  Future<void> _rename(Workspace ws, String path) async {
    final String name = p.basename(path);
    final int dot = name.lastIndexOf('.');
    final String? next = await showInputDialog(context, title: 'Rename', initial: name, selection: TextSelection(baseOffset: 0, extentOffset: dot > 0 ? dot : name.length), confirm: 'Rename');
    if (next == null || next.trim().isEmpty || next == name) return;
    final bool ok = await ws.rename(path, next.trim());
    if (!ok && mounted) context.ide.notifications.error('Could not rename "$name".');
  }

  Future<void> _delete(Workspace ws, String path) async {
    final Ide ide = context.ide;
    if (ide.settings.confirmDelete) {
      final bool ok = await showConfirmDialog(context, title: 'Delete "${p.basename(path)}"?', message: 'This permanently deletes it from disk.', confirm: 'Delete', danger: true);
      if (!ok) return;
    }
    await ws.delete(path);
  }

  void _menu(BuildContext context, Offset pos, Workspace ws, FileNode? node) {
    final Ide ide = context.ide;
    final String? path = node?.path;
    final bool isDir = node?.isDir ?? true;
    final String dir = path == null ? ws.root! : (isDir ? path : p.dirname(path));
    final LanguageDef? lang = path == null || isDir ? null : languageForPath(path);
    showContextMenu(context, pos, [
      MenuEntry('New File…', icon: Icons.note_add_outlined, onTap: () => _newFile(ws, dir)),
      MenuEntry('New Folder…', icon: Icons.create_new_folder_outlined, onTap: () => _newFolder(ws, dir)),
      const MenuEntry.divider(),
      if (lang != null && lang.run != null) MenuEntry('Run File', icon: Icons.play_arrow_rounded, onTap: () async {
        await ws.openFile(path!);
        ide.runActiveFile();
      }),
      if (lang?.id == 'html') MenuEntry('Open with Live Server', icon: Icons.podcasts_rounded, onTap: () => ide.toggleLiveServer(openPath: path)),
      MenuEntry('Reveal in File Explorer', icon: Icons.open_in_new_rounded, shortcut: 'Shift+Alt+R', onTap: () => Ide.revealInOs(path ?? ws.root!)),
      MenuEntry('Open in Integrated Terminal', icon: Icons.terminal_rounded, onTap: () {
        ide.terminals.cwd = dir;
        ide.terminals.create(workingDirectory: dir);
        ide.showPanel(PanelTab.terminal);
      }),
      if (path != null) ...[
        const MenuEntry.divider(),
        MenuEntry('Cut', shortcut: 'Ctrl+X', onTap: () => setState(() {
          _clipboard = path;
          _cut = true;
        })),
        MenuEntry('Copy', shortcut: 'Ctrl+C', onTap: () => setState(() {
          _clipboard = path;
          _cut = false;
        })),
      ],
      MenuEntry('Paste', shortcut: 'Ctrl+V', enabled: _clipboard != null, onTap: _clipboard == null ? null : () => _paste(ws, dir)),
      const MenuEntry.divider(),
      MenuEntry('Copy Path', onTap: () => copyToClipboard(context, path ?? ws.root!)),
      MenuEntry('Copy Relative Path', onTap: () => copyToClipboard(context, ws.relative(path ?? ws.root!))),
      if (path != null) ...[
        const MenuEntry.divider(),
        MenuEntry('Rename…', icon: Icons.drive_file_rename_outline_rounded, shortcut: 'F2', onTap: () => _rename(ws, path)),
        MenuEntry('Delete', icon: Icons.delete_outline_rounded, shortcut: 'Delete', danger: true, onTap: () => _delete(ws, path)),
      ],
    ]);
  }

  Future<void> _paste(Workspace ws, String dir) async {
    final String? src = _clipboard;
    if (src == null) return;
    if (_cut) {
      final String target = p.join(dir, p.basename(src));
      try {
        if (await FileSystemEntity.isDirectory(src)) {
          await Directory(src).rename(target);
        } else {
          await File(src).rename(target);
        }
      } catch (_) {
        await ws.copyInto(src, dir);
        await ws.delete(src);
      }
      _clipboard = null;
      await ws.refreshTree();
    } else {
      await ws.copyInto(src, dir);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e, Workspace ws) {
    if (e is! KeyDownEvent || _selected == null) return KeyEventResult.ignored;
    final bool ctrl = HardwareKeyboard.instance.isControlPressed;
    if (e.logicalKey == LogicalKeyboardKey.f2) {
      _rename(ws, _selected!);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.delete) {
      _delete(ws, _selected!);
      return KeyEventResult.handled;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.keyC) {
      setState(() {
        _clipboard = _selected;
        _cut = false;
      });
      return KeyEventResult.handled;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.keyX) {
      setState(() {
        _clipboard = _selected;
        _cut = true;
      });
      return KeyEventResult.handled;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.keyV) {
      _paste(ws, _targetDir(ws));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter && !FileSystemEntity.isDirectorySync(_selected!)) {
      ws.openFile(_selected!);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final Workspace ws = context.watch<Workspace>();
    final Ide ide = context.read<Ide>();
    final List<EditorTab> open = [for (final EditorGroup g in ws.groups) ...g.tabs];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(title: 'Explorer', actions: [
          IconBtn(icon: Icons.more_horiz_rounded, tooltip: 'Views and More Actions', onTap: () {
            final RenderBox box = context.findRenderObject()! as RenderBox;
            showContextMenu(context, box.localToGlobal(Offset(box.size.width - 200, 30)), [
              MenuEntry('Open Folder…', onTap: () => ide.openFolder()),
              MenuEntry('Close Folder', enabled: ws.hasFolder, onTap: ws.hasFolder ? () => ide.commands.execute('workbench.action.closeFolder') : null),
              MenuEntry('Reveal Folder in File Explorer', enabled: ws.hasFolder, onTap: ws.hasFolder ? () => Ide.revealInOs(ws.root!) : null),
            ]);
          }),
        ]),
        if (open.isNotEmpty) ...[
          PaneHeader(title: 'Open Editors', expanded: _openEditors, onTap: () => setState(() => _openEditors = !_openEditors), actions: [
            IconBtn(icon: Icons.save_outlined, size: 15, tooltip: 'Save All (Ctrl+K S)', onTap: ws.saveAll),
            IconBtn(icon: Icons.close_rounded, size: 15, tooltip: 'Close All', onTap: ws.closeAll),
          ]),
          if (_openEditors)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 6), children: [
                for (final EditorTab tab in open) _OpenEditorRow(tab: tab, active: tab == ws.activeTab),
              ]),
            ),
        ],
        if (!ws.hasFolder)
          Expanded(child: _NoFolder(ide: ide))
        else ...[
          PaneHeader(
            title: ws.folderName,
            expanded: _folder,
            onTap: () => setState(() => _folder = !_folder),
            actions: [
              IconBtn(icon: Icons.note_add_outlined, size: 15, tooltip: 'New File…', onTap: () => _newFile(ws)),
              IconBtn(icon: Icons.create_new_folder_outlined, size: 15, tooltip: 'New Folder…', onTap: () => _newFolder(ws)),
              IconBtn(icon: Icons.refresh_rounded, size: 15, tooltip: 'Refresh Explorer', onTap: ws.refreshTree),
              IconBtn(icon: Icons.unfold_less_rounded, size: 15, tooltip: 'Collapse Folders', onTap: ws.collapseAll),
            ],
          ),
          if (_folder)
            Expanded(
              child: Focus(
                focusNode: _treeFocus,
                onKeyEvent: (n, e) => _onKey(n, e, ws),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onSecondaryTapDown: (d) => _menu(context, d.globalPosition, ws, null),
                  child: Builder(builder: (context) {
                    final List<(FileNode, int)> rows = _flatten(ws.tree!);
                    final String? activePath = ws.activeTab?.path;
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: rows.length,
                      itemExtent: 26,
                      itemBuilder: (context, i) {
                        final (FileNode node, int depth) = rows[i];
                        return _TreeRow(
                          node: node,
                          depth: depth,
                          selected: _selected == node.path,
                          active: activePath != null && p.equals(activePath, node.path),
                          cut: _cut && _clipboard == node.path,
                          onTap: () {
                            _treeFocus.requestFocus();
                            setState(() => _selected = node.path);
                            if (node.isDir) {
                              ws.toggleNode(node);
                            } else {
                              ws.openFile(node.path, preview: true);
                            }
                          },
                          onDoubleTap: node.isDir ? null : () => ws.openFile(node.path),
                          onMenu: (pos) {
                            setState(() => _selected = node.path);
                            _menu(context, pos, ws, node);
                          },
                        );
                      },
                    );
                  }),
                ),
              ),
            )
          else
            const Spacer(),
        ],
      ],
    );
  }
}

class _OpenEditorRow extends StatelessWidget {
  const _OpenEditorRow({required this.tab, required this.active});

  final EditorTab tab;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Workspace ws = context.read<Workspace>();
    return HoverBox(
      selected: active,
      radius: 6,
      onTap: () {
        for (int gi = 0; gi < ws.groups.length; gi++) {
          final int i = ws.groups[gi].tabs.indexOf(tab);
          if (i >= 0) ws.activateTab(gi, i);
        }
      },
      child: SizedBox(
        height: 24,
        child: Row(children: [
          const SizedBox(width: 6),
          HoverBox(onTap: () => ws.closeTab(tab), radius: 4, child: Icon(tab.isDirty ? Icons.circle : Icons.close_rounded, size: tab.isDirty ? 9 : 13, color: t.textMuted)),
          const SizedBox(width: 6),
          if (tab.path != null) FileBadge(path: tab.path!, size: 14) else Icon(Icons.description_outlined, size: 14, color: t.accent),
          const SizedBox(width: 7),
          Flexible(child: Text(tab.title, style: uiText(t, size: 12.5), overflow: TextOverflow.ellipsis)),
          if (tab.path != null && ws.root != null) ...[
            const SizedBox(width: 6),
            Expanded(child: Text(p.dirname(ws.relative(tab.path!)) == '.' ? '' : p.dirname(ws.relative(tab.path!)), style: uiText(t, size: 11, color: t.textFaint), overflow: TextOverflow.ellipsis)),
          ],
        ]),
      ),
    );
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.node,
    required this.depth,
    required this.selected,
    required this.active,
    required this.cut,
    required this.onTap,
    required this.onDoubleTap,
    required this.onMenu,
  });

  final FileNode node;
  final int depth;
  final bool selected;
  final bool active;
  final bool cut;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Workspace ws = context.read<Workspace>();
    String? git = ws.gitStatus[node.path];
    if (git == null && node.isDir) {
      // Folders show a dot when something inside changed.
      final String prefix = '${node.path}${Platform.pathSeparator}';
      if (ws.gitStatus.keys.any((k) => k.startsWith(prefix))) git = '•';
    }
    final List<Diagnostic>? diags = node.isDir ? null : ws.diagnostics[node.path];
    final int errors = diags?.where((d) => d.severity == DiagnosticSeverity.error).length ?? 0;
    final int warnings = diags?.where((d) => d.severity == DiagnosticSeverity.warning).length ?? 0;
    Color color = t.text;
    if (errors > 0) {
      color = t.error;
    } else if (warnings > 0) {
      color = t.warning;
    } else if (git == 'M' || git == '•') {
      color = t.gitModified;
    } else if (git == 'U' || git == 'A') {
      color = t.gitAdded;
    } else if (git == 'D') {
      color = t.gitDeleted;
    }
    if (node.name.startsWith('.') && git == null) color = t.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: HoverBox(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onSecondaryTapDown: (d) => onMenu(d.globalPosition),
        selected: selected || active,
        selectedColor: active ? t.accentSoft : t.hover,
        radius: 6,
        child: Opacity(
          opacity: cut ? 0.5 : 1,
          child: Row(children: [
            SizedBox(width: 8.0 + depth * 14),
            // Indentation guides are implied by spacing; chevron for folders.
            SizedBox(
              width: 16,
              child: node.isDir
                  ? AnimatedRotation(
                      turns: node.expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: Icon(Icons.chevron_right_rounded, size: 16, color: t.textMuted),
                    )
                  : null,
            ),
            const SizedBox(width: 4),
            FileBadge(path: node.path, isDir: node.isDir, open: node.expanded, size: 15),
            const SizedBox(width: 8),
            Expanded(child: Text(node.name, style: uiText(t, size: 13, color: color), overflow: TextOverflow.ellipsis)),
            if (errors + warnings > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(color: (errors > 0 ? t.error : t.warning).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                child: Text('${errors + warnings}', style: uiText(t, size: 10.5, color: errors > 0 ? t.error : t.warning, weight: FontWeight.w700)),
              ),
            if (git != null)
              SizedBox(width: 16, child: Text(git, textAlign: TextAlign.center, style: uiText(t, size: 11, color: color, weight: FontWeight.w700))),
            const SizedBox(width: 6),
          ]),
        ),
      ),
    );
  }
}

class _NoFolder extends StatelessWidget {
  const _NoFolder({required this.ide});

  final Ide ide;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('You have not yet opened a folder.', style: uiText(t, color: t.textMuted)),
        const SizedBox(height: 14),
        AccentButton(label: 'Open Folder', icon: Icons.folder_open_rounded, onTap: () => ide.openFolder()),
        const SizedBox(height: 10),
        AccentButton(label: 'Open File', subtle: true, icon: Icons.file_open_outlined, onTap: ide.openFileDialog),
        const SizedBox(height: 18),
        if (ide.settings.recentFolders.isNotEmpty) ...[
          Text('RECENT', style: uiText(t, size: 11, weight: FontWeight.w600, color: t.textFaint).copyWith(letterSpacing: 0.8)),
          const SizedBox(height: 6),
          for (final String f in ide.settings.recentFolders.take(6))
            HoverBox(
              onTap: () => ide.openFolder(f),
              radius: 6,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(children: [
                Icon(Icons.history_rounded, size: 15, color: t.textMuted),
                const SizedBox(width: 8),
                Expanded(child: Text(p.basename(f), style: uiText(t, size: 13), overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ],
      ]),
    );
  }
}
