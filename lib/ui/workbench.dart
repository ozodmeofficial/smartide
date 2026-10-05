import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../app/ide.dart';
import '../theme/ide_theme.dart';
import 'activity_bar.dart';
import 'assistant_panel.dart';
import 'editor/editor_area.dart';
import 'panel/panel.dart';
import 'quick_pick_overlay.dart';
import 'sidebar/explorer_view.dart';
import 'sidebar/extensions_view.dart';
import 'sidebar/run_view.dart';
import 'sidebar/scm_view.dart';
import 'sidebar/search_view.dart';
import 'status_bar.dart';
import 'title_bar.dart';
import 'toasts.dart';
import 'widgets.dart';

class Workbench extends StatefulWidget {
  const Workbench({super.key});

  @override
  State<Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<Workbench> with WindowListener {
  final FocusNode _rootFocus = FocusNode(debugLabel: 'workbench');

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _rootFocus.dispose();
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    final Ide ide = context.read<Ide>();
    if (await ide.confirmQuit()) {
      await ide.settings.saveNow();
      ide.terminals.closeAll();
      await ide.liveServer.stop();
      await windowManager.destroy();
    }
  }

  @override
  void onWindowBlur() => context.read<Ide>().workspace.onWindowBlur();

  @override
  Widget build(BuildContext context) {
    final Ide ide = context.watch<Ide>();
    final IdeTheme t = ide.effectiveTheme;
    final bool zen = ide.zenMode;
    return Focus(
      focusNode: _rootFocus,
      autofocus: true,
      onKeyEvent: (node, e) => ide.handleKey(e) ? KeyEventResult.handled : KeyEventResult.ignored,
      child: Material(
        color: t.chrome,
        child: Stack(children: [
          Column(children: [
            if (!ide.fullScreen) const TitleBar(),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (!zen) const ActivityBar(),
                if (!zen && ide.sidebarVisible) ...[
                  SizedBox(width: ide.settings.sidebarWidth, child: const _SideBar()),
                  Splitter(
                    axis: Axis.horizontal,
                    onDrag: (dx) {
                      ide.settings.updateSilently((s) => s.sidebarWidth = (s.sidebarWidth + dx).clamp(170, 700));
                      ide.touch();
                    },
                  ),
                ] else
                  const SizedBox(width: 6),
                Expanded(child: _Center(zen: zen)),
                if (ide.assistantVisible && ide.extensions.isEnabled('smartide.assistant')) ...[
                  Splitter(
                    axis: Axis.horizontal,
                    onDrag: (dx) {
                      ide.settings.updateSilently((s) => s.assistantWidth = (s.assistantWidth - dx).clamp(280, 800));
                      ide.touch();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 6),
                    child: SizedBox(width: ide.settings.assistantWidth, child: const AssistantPanel()),
                  ),
                ] else
                  const SizedBox(width: 6),
              ]),
            ),
            if (!zen) const StatusBar(),
          ]),
          if (ide.quickPick != null) Positioned.fill(child: QuickPickOverlay(request: ide.quickPick!)),
          const ToastLayer(),
        ]),
      ),
    );
  }
}

class _SideBar extends StatelessWidget {
  const _SideBar();

  @override
  Widget build(BuildContext context) {
    final Ide ide = context.watch<Ide>();
    return switch (ide.sideView) {
      SideView.explorer => const ExplorerView(),
      SideView.search => const SearchView(),
      SideView.scm => const ScmView(),
      SideView.run => const RunView(),
      SideView.extensions => const ExtensionsView(),
    };
  }
}

class _Center extends StatelessWidget {
  const _Center({required this.zen});

  final bool zen;

  @override
  Widget build(BuildContext context) {
    final Ide ide = context.watch<Ide>();
    final bool panel = ide.panelVisible && !zen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: LayoutBuilder(builder: (context, box) {
        final double maxPanel = box.maxHeight - 120;
        final double panelH = ide.panelMaximized ? maxPanel : ide.settings.panelHeight.clamp(100, maxPanel < 100 ? 100 : maxPanel);
        return Column(children: [
          const Expanded(child: EditorArea()),
          if (panel) ...[
            Splitter(
              axis: Axis.vertical,
              onDrag: (dy) {
                ide.panelMaximized = false;
                ide.settings.updateSilently((s) => s.panelHeight = (s.panelHeight - dy).clamp(100, maxPanel));
                ide.touch();
              },
            ),
            SizedBox(height: panelH, child: const BottomPanel()),
          ],
        ]);
      }),
    );
  }
}
