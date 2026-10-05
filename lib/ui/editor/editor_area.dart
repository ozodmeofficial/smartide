import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';

import '../../app/ide.dart';
import '../../theme/ide_theme.dart';
import '../../workspace/editor_document.dart';
import '../../workspace/workspace.dart';
import '../logo.dart';
import '../pages/extension_detail.dart';
import '../pages/keybindings_page.dart';
import '../pages/markdown_view.dart';
import '../pages/settings_page.dart';
import '../pages/welcome_page.dart';
import '../widgets.dart';
import 'code_editor_view.dart';

class EditorArea extends StatefulWidget {
  const EditorArea({super.key});

  @override
  State<EditorArea> createState() => _EditorAreaState();
}

class _EditorAreaState extends State<EditorArea> {
  double _split = 0.5;

  @override
  Widget build(BuildContext context) {
    final Workspace ws = context.watch<Workspace>();
    if (ws.groups.length == 1) return const EditorGroupView(groupIndex: 0);
    return LayoutBuilder(builder: (context, box) {
      final double w = box.maxWidth;
      return Row(
        children: [
          SizedBox(width: (w - 6) * _split, child: const EditorGroupView(groupIndex: 0)),
          Splitter(axis: Axis.horizontal, onDrag: (dx) => setState(() => _split = (_split + dx / w).clamp(0.15, 0.85))),
          const Expanded(child: EditorGroupView(groupIndex: 1)),
        ],
      );
    });
  }
}

class EditorGroupView extends StatelessWidget {
  const EditorGroupView({super.key, required this.groupIndex});

  final int groupIndex;

  @override
  Widget build(BuildContext context) {
    final Workspace ws = context.watch<Workspace>();
    final Ide ide = context.read<Ide>();
    if (groupIndex >= ws.groups.length) return const SizedBox.shrink();
    final EditorGroup g = ws.groups[groupIndex];
    final EditorTab? active = g.activeTab;
    final bool focused = ws.activeGroupIndex == groupIndex;
    return Listener(
      onPointerDown: (_) {
        if (!focused) ws.focusGroup(groupIndex);
      },
      child: Card2(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (g.tabs.isNotEmpty) _TabStrip(groupIndex: groupIndex, focused: focused),
            if (active != null && active.kind == TabKind.text && ide.settings.showBreadcrumbs) _Breadcrumbs(tab: active),
            Expanded(
              child: g.tabs.isEmpty
                  ? const _EmptyEditor()
                  : IndexedStack(
                      index: g.active.clamp(0, g.tabs.length - 1),
                      sizing: StackFit.expand,
                      children: [
                        for (final EditorTab tab in g.tabs)
                          KeyedSubtree(
                            key: ValueKey('${groupIndex}_${tab.id}'),
                            child: _TabContent(tab: tab, active: tab == active && focused, secondary: groupIndex > 0 && tab.document != null && ws.groups[0].tabs.any((x) => x.document == tab.document)),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabContent extends StatelessWidget {
  const _TabContent({required this.tab, required this.active, required this.secondary});

  final EditorTab tab;
  final bool active;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    switch (tab.kind) {
      case TabKind.text:
        return secondary ? _SecondaryEditor(doc: tab.document!, active: active) : CodeEditorView(doc: tab.document!, active: active);
      case TabKind.welcome:
        return const WelcomePage();
      case TabKind.settings:
        return const SettingsPage();
      case TabKind.keybindings:
        return const KeybindingsPage();
      case TabKind.extension:
        return ExtensionDetailPage(id: '${tab.extra}');
      case TabKind.markdownPreview:
        return MarkdownPreviewPage(path: tab.path!);
      case TabKind.image:
        return _ImageViewer(path: tab.path!);
      case TabKind.binary:
      case TabKind.diff:
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.insert_drive_file_outlined, size: 48, color: t.textFaint),
            const SizedBox(height: 12),
            Text('This file is binary or uses an unsupported encoding.', style: uiText(t, color: t.textMuted)),
            const SizedBox(height: 12),
            AccentButton(label: 'Reveal in File Explorer', subtle: true, onTap: () => Ide.revealInOs(tab.path!)),
          ]),
        );
    }
  }
}

/// Second view of a document already open in the first group: it needs its
/// own focus node and scroll controller.
class _SecondaryEditor extends StatefulWidget {
  const _SecondaryEditor({required this.doc, required this.active});

  final EditorDocument doc;
  final bool active;

  @override
  State<_SecondaryEditor> createState() => _SecondaryEditorState();
}

class _SecondaryEditorState extends State<_SecondaryEditor> {
  final FocusNode _focus = FocusNode();
  final CodeScrollController _scroll = CodeScrollController();
  late final CodeFindController _find = CodeFindController(widget.doc.controller);

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    _find.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Ide ide = context.watch<Ide>();
    final s = ide.settings;
    return CodeEditor(
      controller: widget.doc.controller,
      focusNode: _focus,
      scrollController: _scroll,
      findController: _find,
      autofocus: widget.active,
      wordWrap: s.wordWrap,
      shortcutsActivatorsBuilder: const VsCodeShortcuts(),
      commentFormatter: LanguageCommentFormatter(widget.doc),
      padding: const EdgeInsets.only(left: 4, top: 6, bottom: 120, right: 16),
      style: CodeEditorStyle(
        fontSize: s.editorFontSize,
        fontFamily: ide.fonts.isLoaded(s.editorFont) ? s.editorFont : 'JetBrains Mono',
        fontHeight: s.lineHeight,
        textColor: t.text,
        backgroundColor: t.editorBg,
        selectionColor: t.selection,
        cursorColor: t.accent,
        cursorLineColor: s.highlightActiveLine ? t.lineHighlight : null,
        codeTheme: CodeHighlightTheme(languages: {widget.doc.language.id: CodeHighlightThemeMode(mode: widget.doc.language.mode)}, theme: t.syntax),
      ),
      indicatorBuilder: (context, editingController, chunkController, notifier) => Row(children: [
        DefaultCodeLineNumber(controller: editingController, notifier: notifier, textStyle: TextStyle(color: t.textFaint, fontSize: s.editorFontSize * 0.9)),
        DefaultCodeChunkIndicator(width: 18, controller: chunkController, notifier: notifier),
      ]),
    );
  }
}

class _TabStrip extends StatefulWidget {
  const _TabStrip({required this.groupIndex, required this.focused});

  final int groupIndex;
  final bool focused;

  @override
  State<_TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<_TabStrip> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Workspace ws = context.watch<Workspace>();
    final Ide ide = context.read<Ide>();
    final IdeTheme t = context.t;
    final EditorGroup g = ws.groups[widget.groupIndex];
    final EditorTab? active = g.activeTab;
    final bool runnable = active?.document != null && (active!.document!.language.run != null || active.document!.language.id == 'html');
    return Container(
      height: 38,
      decoration: BoxDecoration(color: t.chrome.withValues(alpha: t.isDark ? 0.55 : 0.6), border: Border(bottom: BorderSide(color: t.border))),
      child: Row(
        children: [
          Expanded(
            child: Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent && _scroll.hasClients) {
                  _scroll.jumpTo((_scroll.offset + e.scrollDelta.dy + e.scrollDelta.dx).clamp(0, _scroll.position.maxScrollExtent));
                }
              },
              child: ReorderableListView.builder(
                scrollController: _scroll,
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(left: 4, top: 4),
                proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
                itemCount: g.tabs.length,
                onReorderItem: (from, to) => ws.moveTab(widget.groupIndex, from, to),
                itemBuilder: (context, i) => ReorderableDragStartListener(
                  key: ValueKey(g.tabs[i].id),
                  index: i,
                  child: _TabChip(
                    tab: g.tabs[i],
                    active: i == g.active,
                    groupFocused: widget.focused,
                    onTap: () => ws.activateTab(widget.groupIndex, i),
                  ),
                ),
              ),
            ),
          ),
          if (runnable) IconBtn(icon: Icons.play_arrow_rounded, color: t.success, size: 19, tooltip: 'Run File (F5)', onTap: ide.runActiveFile),
          if (active?.document?.language.id == 'markdown')
            IconBtn(icon: Icons.chrome_reader_mode_outlined, tooltip: 'Open Preview to the Side', onTap: () => ws.openSpecial(TabKind.markdownPreview, path: active!.path)),
          IconBtn(icon: Icons.vertical_split_outlined, tooltip: 'Split Editor Right (Ctrl+\\)', onTap: ws.splitEditor),
          IconBtn(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More Actions…',
            onTap: () {
              final RenderBox box = context.findRenderObject()! as RenderBox;
              final Offset pos = box.localToGlobal(Offset(box.size.width - 230, box.size.height));
              showContextMenu(context, pos, [
                MenuEntry('Close All', onTap: ws.closeAll, shortcut: 'Ctrl+K Ctrl+W'),
                MenuEntry('Close Saved', onTap: ws.closeSaved),
                const MenuEntry.divider(),
                MenuEntry('Toggle Word Wrap', onTap: ide.toggleWordWrap, shortcut: 'Alt+Z'),
                MenuEntry('Toggle Minimap', onTap: () => ide.settings.update((s) => s.minimap = !s.minimap)),
                MenuEntry('Toggle Breadcrumbs', onTap: () => ide.settings.update((s) => s.showBreadcrumbs = !s.showBreadcrumbs)),
              ]);
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
  const _TabChip({required this.tab, required this.active, required this.groupFocused, required this.onTap});

  final EditorTab tab;
  final bool active;
  final bool groupFocused;
  final VoidCallback onTap;

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hover = false;

  IconData? _specialIcon(TabKind k) => switch (k) {
        TabKind.welcome => Icons.waving_hand_outlined,
        TabKind.settings => Icons.tune_rounded,
        TabKind.keybindings => Icons.keyboard_outlined,
        TabKind.extension => Icons.extension_outlined,
        TabKind.markdownPreview => Icons.chrome_reader_mode_outlined,
        TabKind.image => Icons.image_outlined,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Workspace ws = context.read<Workspace>();
    final EditorTab tab = widget.tab;
    final bool dirty = tab.isDirty;
    final String? path = tab.path;
    final int errors = path == null ? 0 : (ws.diagnostics[path]?.where((d) => d.severity == DiagnosticSeverity.error).length ?? 0);
    final String? git = path == null ? null : ws.gitStatus[path];
    Color titleColor = widget.active ? t.text : t.textMuted;
    if (errors > 0) {
      titleColor = t.error;
    } else if (git == 'M') {
      titleColor = t.gitModified;
    } else if (git == 'U' || git == 'A') {
      titleColor = t.gitAdded;
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerDown: (e) {
          if (e.buttons == kMiddleMouseButton) ws.closeTab(tab);
        },
        child: GestureDetector(
          onTap: widget.onTap,
          onDoubleTap: () => ws.pinPreview(tab),
          onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.only(right: 2),
            padding: const EdgeInsets.only(left: 10, right: 4),
            constraints: const BoxConstraints(minWidth: 90, maxWidth: 240),
            decoration: BoxDecoration(
              color: widget.active ? t.editorBg : (_hover ? t.hover : Colors.transparent),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: widget.active ? Border.all(color: t.border) : null,
            ),
            foregroundDecoration: widget.active
                ? BoxDecoration(
                    border: Border(top: BorderSide(color: widget.groupFocused ? t.accent : t.borderStrong, width: 2)),
                  )
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tab.kind == TabKind.text || tab.kind == TabKind.binary)
                  FileBadge(path: path ?? tab.title, size: 15)
                else
                  Icon(_specialIcon(tab.kind) ?? Icons.description_outlined, size: 15, color: t.accent),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    tab.title,
                    overflow: TextOverflow.ellipsis,
                    style: uiText(t, size: 12.5, color: titleColor, weight: widget.active ? FontWeight.w500 : FontWeight.w400).copyWith(fontStyle: tab.preview ? FontStyle.italic : null),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: (_hover || widget.active) && !(dirty && !_hover)
                      ? HoverBox(
                          onTap: () => ws.closeTab(tab),
                          radius: 5,
                          tooltip: 'Close (Ctrl+W)',
                          child: Icon(Icons.close_rounded, size: 14, color: t.textMuted),
                        )
                      : dirty
                          ? Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(color: t.text.withValues(alpha: 0.7), shape: BoxShape.circle)))
                          : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _menu(BuildContext context, Offset pos) {
    final Workspace ws = context.read<Workspace>();
    final Ide ide = context.read<Ide>();
    final EditorTab tab = widget.tab;
    final String? path = tab.path;
    showContextMenu(context, pos, [
      MenuEntry('Close', shortcut: 'Ctrl+W', onTap: () => ws.closeTab(tab)),
      MenuEntry('Close Others', onTap: () => ws.closeOthers(tab)),
      MenuEntry('Close to the Right', onTap: () async {
        final EditorGroup g = ws.groups.firstWhere((g) => g.tabs.contains(tab));
        final int i = g.tabs.indexOf(tab);
        for (final EditorTab x in g.tabs.sublist(i + 1).toList()) {
          await ws.closeTab(x);
        }
      }),
      MenuEntry('Close Saved', onTap: ws.closeSaved),
      MenuEntry('Close All', onTap: ws.closeAll),
      const MenuEntry.divider(),
      MenuEntry('Copy Path', enabled: path != null, onTap: path == null ? null : () => copyToClipboard(context, path)),
      MenuEntry('Copy Relative Path', enabled: path != null, onTap: path == null ? null : () => copyToClipboard(context, ws.relative(path))),
      MenuEntry('Reveal in File Explorer', enabled: path != null, onTap: path == null ? null : () => Ide.revealInOs(path)),
      MenuEntry('Reveal in Explorer View', enabled: path != null, onTap: path == null ? null : () {
        ws.reveal(path);
        ide.showView(SideView.explorer);
      }),
      const MenuEntry.divider(),
      MenuEntry('Split Right', onTap: ws.splitEditor),
      MenuEntry(tab.pinned ? 'Unpin' : 'Pin', onTap: () {
        tab.pinned = !tab.pinned;
        tab.preview = false;
        ws.touch();
      }),
    ]);
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.tab});

  final EditorTab tab;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Workspace ws = context.read<Workspace>();
    final Ide ide = context.read<Ide>();
    final String? path = tab.path;
    final List<String> parts = path == null ? [tab.title] : p.split(ws.relative(path));
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (int i = 0; i < parts.length; i++) ...[
            if (i > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: Icon(Icons.chevron_right_rounded, size: 14, color: t.textFaint)),
            if (i == parts.length - 1) ...[FileBadge(path: parts[i], size: 13), const SizedBox(width: 5)],
            HoverBox(
              radius: 4,
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              onTap: path == null
                  ? null
                  : () {
                      if (i < parts.length - 1) {
                        ws.reveal(p.join(ws.root ?? '', p.joinAll(parts.sublist(0, i + 1)), 'x'));
                        ide.showView(SideView.explorer);
                      } else {
                        ide.showQuickOpen();
                      }
                    },
              child: Text(parts[i], style: uiText(t, size: 12, color: i == parts.length - 1 ? t.text : t.textMuted)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor();

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Ide ide = context.read<Ide>();
    final List<(String, String)> rows = [
      ('Show All Commands', 'workbench.action.showCommands'),
      ('Go to File', 'workbench.action.quickOpen'),
      ('Find in Files', 'workbench.view.search'),
      ('Run File', 'workbench.action.debug.start'),
      ('Toggle Terminal', 'workbench.action.terminal.toggleTerminal'),
      ('Ask the Assistant', 'workbench.action.toggleAssistant'),
    ];
    return Center(
      child: Opacity(
        opacity: 0.9,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(opacity: 0.25, child: const SmartIdeLogo(size: 110)),
            const SizedBox(height: 28),
            for (final (String label, String id) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 170, child: Text(label, textAlign: TextAlign.right, style: uiText(t, color: t.textMuted))),
                  const SizedBox(width: 14),
                  SizedBox(width: 170, child: Align(alignment: Alignment.centerLeft, child: Kbd(ide.commands.shortcutFor(id) ?? '—'))),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.path});

  final String path;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  final TransformationController _tc = TransformationController();

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final File f = File(widget.path);
    return Column(
      children: [
        Expanded(
          child: InteractiveViewer(
            transformationController: _tc,
            minScale: 0.1,
            maxScale: 20,
            boundaryMargin: const EdgeInsets.all(400),
            child: Center(child: Image.file(f, filterQuality: FilterQuality.medium, errorBuilder: (_, _, _) => Text('Cannot display image', style: uiText(t)))),
          ),
        ),
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: FutureBuilder<int>(
            future: f.length(),
            builder: (_, s) => Text('${p.basename(widget.path)}  ·  ${s.hasData ? _size(s.data!) : ''}', style: uiText(t, size: 12, color: t.textMuted)),
          ),
        ),
      ],
    );
  }

  static String _size(int b) => b < 1024 ? '$b B' : (b < 1048576 ? '${(b / 1024).toStringAsFixed(1)} KB' : '${(b / 1048576).toStringAsFixed(1)} MB');
}
