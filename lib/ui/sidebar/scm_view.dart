import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../app/ide.dart';
import '../../services/git_service.dart';
import '../../theme/ide_theme.dart';
import '../widgets.dart';

class ScmView extends StatefulWidget {
  const ScmView({super.key});

  @override
  State<ScmView> createState() => _ScmViewState();
}

class _ScmViewState extends State<ScmView> {
  final TextEditingController _msg = TextEditingController();
  bool _stagedOpen = true;
  bool _changesOpen = true;
  bool _historyOpen = false;

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _commit(GitService git, Ide ide) async {
    final bool ok = await git.commit(_msg.text, all: git.staged.isEmpty);
    if (ok) {
      _msg.clear();
      ide.notifications.success('Committed');
      if (_historyOpen) git.loadLog();
    } else {
      ide.notifications.error('Commit failed', detail: git.lastError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final GitService git = context.watch<GitService>();
    final Ide ide = context.read<Ide>();
    if (!ide.extensions.isEnabled('smartide.git')) {
      return _Empty(text: 'The Git extension is disabled.', action: 'Enable', onTap: () => ide.extensions.setEnabled('smartide.git', true));
    }
    if (!git.available) {
      return _Empty(text: 'Git is not installed on this computer.\nInstall it to use source control.', action: 'Install Git (winget)', onTap: () {
        ide.showPanel(PanelTab.terminal);
        ide.terminals.sendToActive('winget install --id Git.Git -e');
      });
    }
    if (!ide.workspace.hasFolder) {
      return _Empty(text: 'Open a folder to use source control.', action: 'Open Folder', onTap: () => ide.openFolder());
    }
    if (!git.isRepo) {
      return _Empty(text: 'The folder currently open does not have a Git repository.', action: 'Initialize Repository', onTap: git.initRepo);
    }
    final List<GitChange> staged = git.staged;
    final List<GitChange> changes = git.unstaged;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PaneHeader(title: 'Source Control', actions: [
        IconBtn(icon: Icons.check_rounded, size: 16, tooltip: 'Commit (Ctrl+Enter)', onTap: () => _commit(git, ide)),
        IconBtn(icon: Icons.refresh_rounded, size: 15, tooltip: 'Refresh', onTap: git.refresh),
        IconBtn(icon: Icons.more_horiz_rounded, size: 15, tooltip: 'More Actions', onTap: () {
          final RenderBox box = context.findRenderObject()! as RenderBox;
          showContextMenu(context, box.localToGlobal(Offset(box.size.width - 220, 30)), [
            MenuEntry('Pull', icon: Icons.download_rounded, onTap: () => ide.commands.execute('git.pull')),
            MenuEntry('Push', icon: Icons.upload_rounded, onTap: () => ide.commands.execute('git.push')),
            MenuEntry('Fetch', icon: Icons.sync_rounded, onTap: () => ide.commands.execute('git.fetch')),
            const MenuEntry.divider(),
            MenuEntry('Checkout to…', icon: Icons.call_split_rounded, onTap: ide.showBranchPicker),
            MenuEntry('Stash Changes', onTap: () => ide.commands.execute('git.stash')),
            MenuEntry('Pop Stash', onTap: () => ide.commands.execute('git.stashPop')),
            const MenuEntry.divider(),
            MenuEntry('Commit (Amend)', onTap: () => git.commit(_msg.text, amend: true)),
            MenuEntry('Show Git Output', onTap: () {
              ide.output.select('Git');
              ide.showPanel(PanelTab.output);
            }),
          ]);
        }),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _commit(git, ide)},
          child: IdeTextField(controller: _msg, hint: 'Message (Ctrl+Enter to commit on "${git.branch}")', maxLines: 5, minLines: 1),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Row(children: [
          Expanded(
            child: AccentButton(
              label: git.busy ? 'Working…' : (staged.isEmpty && changes.isNotEmpty ? 'Commit All' : 'Commit'),
              icon: Icons.check_rounded,
              onTap: git.busy || (staged.isEmpty && changes.isEmpty) ? null : () => _commit(git, ide),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: git.upstream == null ? 'Publish Branch' : 'Sync Changes (${git.behind}↓ ${git.ahead}↑)',
            child: AccentButton(
              label: git.upstream == null ? 'Publish' : '${git.behind}↓ ${git.ahead}↑',
              subtle: true,
              icon: git.upstream == null ? Icons.cloud_upload_outlined : Icons.sync_rounded,
              onTap: git.busy ? null : () => ide.commands.execute(git.upstream == null ? 'git.push' : 'git.sync'),
            ),
          ),
        ]),
      ),
      if (git.busy) LinearProgressIndicator(minHeight: 2, color: t.accent, backgroundColor: Colors.transparent),
      Expanded(
        child: ListView(padding: const EdgeInsets.only(bottom: 20), children: [
          if (staged.isNotEmpty) ...[
            PaneHeader(title: 'Staged Changes', expanded: _stagedOpen, onTap: () => setState(() => _stagedOpen = !_stagedOpen), actions: [
              IconBtn(icon: Icons.remove_rounded, size: 15, tooltip: 'Unstage All Changes', onTap: git.unstageAll),
              _CountBadge(staged.length),
            ]),
            if (_stagedOpen) for (final GitChange c in staged) _ChangeRow(change: c, staged: true),
          ],
          PaneHeader(title: 'Changes', expanded: _changesOpen, onTap: () => setState(() => _changesOpen = !_changesOpen), actions: [
            if (changes.isNotEmpty) IconBtn(icon: Icons.add_rounded, size: 15, tooltip: 'Stage All Changes', onTap: git.stageAll),
            _CountBadge(changes.length),
          ]),
          if (_changesOpen)
            if (changes.isEmpty)
              Padding(padding: const EdgeInsets.fromLTRB(28, 4, 12, 8), child: Text('No changes. Working tree is clean ✨', style: uiText(t, size: 12.5, color: t.textFaint)))
            else
              for (final GitChange c in changes) _ChangeRow(change: c, staged: false),
          PaneHeader(title: 'History', expanded: _historyOpen, onTap: () {
            setState(() => _historyOpen = !_historyOpen);
            if (_historyOpen) git.loadLog();
          }),
          if (_historyOpen)
            for (final GitCommitInfo c in git.log)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: HoverBox(
                  radius: 6,
                  tooltip: '${c.hash} · ${c.author} · ${c.date}',
                  onTap: () => copyToClipboard(context, c.hash, message: 'Commit hash copied'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Row(children: [
                    Icon(Icons.commit_rounded, size: 15, color: t.accent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(c.subject, style: uiText(t, size: 12.5), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    Text(c.date.replaceAll(' ago', ''), style: uiText(t, size: 11, color: t.textFaint)),
                  ]),
                ),
              ),
        ]),
      ),
    ]);
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.n);

  final int n;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: t.hover, borderRadius: BorderRadius.circular(8)),
      child: Text('$n', style: uiText(t, size: 10.5, color: t.textMuted)),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change, required this.staged});

  final GitChange change;
  final bool staged;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final GitService git = context.read<GitService>();
    final Ide ide = context.read<Ide>();
    final String letter = change.letterFor(stagedView: staged);
    final Color c = switch (letter) {
      'U' || 'A' => t.gitAdded,
      'D' => t.gitDeleted,
      '!' => t.error,
      _ => t.gitModified,
    };
    final String rel = ide.workspace.relative(p.dirname(change.path));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: _HoverActions(
        onTap: () async {
          if (letter == 'D') return;
          await ide.workspace.openFile(change.path, preview: true);
        },
        actions: [
          if (!staged)
            IconBtn(icon: Icons.undo_rounded, size: 14, box: 22, tooltip: 'Discard Changes', onTap: () => git.discard(change)),
          IconBtn(
            icon: staged ? Icons.remove_rounded : Icons.add_rounded,
            size: 15,
            box: 22,
            tooltip: staged ? 'Unstage Changes' : 'Stage Changes',
            onTap: () => staged ? git.unstage([change.path]) : git.stage([change.path]),
          ),
        ],
        child: Row(children: [
          const SizedBox(width: 22),
          FileBadge(path: change.path, size: 14),
          const SizedBox(width: 7),
          Text(p.basename(change.path), style: uiText(t, size: 12.5, color: letter == 'D' ? t.textMuted : t.text).copyWith(decoration: letter == 'D' ? TextDecoration.lineThrough : null)),
          const SizedBox(width: 6),
          Expanded(child: Text(rel == '.' ? '' : rel, style: uiText(t, size: 11, color: t.textFaint), overflow: TextOverflow.ellipsis)),
          SizedBox(width: 18, child: Text(letter, textAlign: TextAlign.center, style: uiText(t, size: 11.5, color: c, weight: FontWeight.w700))),
          const SizedBox(width: 4),
        ]),
      ),
    );
  }
}

class _HoverActions extends StatefulWidget {
  const _HoverActions({required this.child, required this.actions, required this.onTap});

  final Widget child;
  final List<Widget> actions;
  final VoidCallback onTap;

  @override
  State<_HoverActions> createState() => _HoverActionsState();
}

class _HoverActionsState extends State<_HoverActions> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: HoverBox(
        onTap: widget.onTap,
        radius: 6,
        child: SizedBox(
          height: 24,
          child: Stack(children: [
            Positioned.fill(child: widget.child),
            if (_hover)
              Positioned(
                right: 22,
                top: 1,
                child: Container(color: context.t.surface.withValues(alpha: 0.0), child: Row(children: widget.actions)),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, required this.action, required this.onTap});

  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const PaneHeader(title: 'Source Control'),
      Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(Icons.account_tree_outlined, size: 40, color: t.textFaint),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: uiText(t, color: t.textMuted)),
          const SizedBox(height: 14),
          AccentButton(label: action, onTap: onTap),
        ]),
      ),
    ]);
  }
}
