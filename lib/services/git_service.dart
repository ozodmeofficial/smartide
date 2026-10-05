import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../workspace/workspace.dart';
import 'output_service.dart';

class GitChange {
  GitChange(this.path, this.index, this.work, {this.origPath});

  /// Absolute path.
  final String path;
  final String index;
  final String work;
  final String? origPath;

  bool get staged => index != ' ' && index != '?';
  bool get unstaged => work != ' ';
  bool get untracked => index == '?';
  bool get conflicted => index == 'U' || work == 'U' || (index == 'A' && work == 'A') || (index == 'D' && work == 'D');

  /// Letter shown next to the file in the UI.
  String letterFor({required bool stagedView}) {
    if (untracked) return 'U';
    if (conflicted) return '!';
    final String c = stagedView ? index : work;
    return c == ' ' ? 'M' : c;
  }
}

class GitCommitInfo {
  GitCommitInfo(this.hash, this.author, this.date, this.subject);

  final String hash;
  final String author;
  final String date;
  final String subject;
}

/// Thin wrapper around the git CLI.
class GitService extends ChangeNotifier {
  GitService(this.workspace, this.output) {
    workspace.onFilesChanged.add(_scheduleRefresh);
    workspace.onDocumentSaved.add((_) => _scheduleRefresh());
  }

  final Workspace workspace;
  final OutputService output;

  bool available = false;
  bool isRepo = false;
  bool busy = false;
  String branch = '';
  String? upstream;
  int ahead = 0;
  int behind = 0;
  List<GitChange> changes = [];
  List<String> branches = [];
  List<GitCommitInfo> log = [];
  String? lastError;
  Timer? _timer;

  List<GitChange> get staged => changes.where((c) => c.staged && !c.untracked).toList();
  List<GitChange> get unstaged => changes.where((c) => c.unstaged || c.untracked).toList();
  int get changeCount => changes.length;

  String? get _root => workspace.root;

  Future<void> init() async {
    try {
      final ProcessResult r = await Process.run('git', ['--version']);
      available = r.exitCode == 0;
    } catch (_) {
      available = false;
    }
    await refresh();
  }

  void _scheduleRefresh() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), refresh);
  }

  Future<ProcessResult> _git(List<String> args, {bool log = true}) async {
    ProcessResult r;
    try {
      final String? root = _root;
      if (root != null && !await Directory(root).exists()) {
        return ProcessResult(0, 128, '', 'folder no longer exists');
      }
      r = await Process.run(
        'git',
        ['-c', 'core.quotepath=false', '-c', 'color.ui=false', ...args],
        workingDirectory: root,
        environment: {'GIT_TERMINAL_PROMPT': '0', 'LC_ALL': 'C.UTF-8'},
        stdoutEncoding: const SystemEncodingUtf8(),
        stderrEncoding: const SystemEncodingUtf8(),
      );
    } on ProcessException catch (e) {
      r = ProcessResult(0, 127, '', e.message);
    }
    if (log) {
      output.append('Git', '> git ${args.join(' ')}');
      if (r.exitCode != 0) output.append('Git', '${r.stderr}');
    }
    return r;
  }

  Future<void> refresh() async {
    if (!available || _root == null) {
      isRepo = false;
      changes = [];
      workspace.setGitStatus({});
      notifyListeners();
      return;
    }
    final ProcessResult inside = await _git(['rev-parse', '--is-inside-work-tree'], log: false);
    isRepo = inside.exitCode == 0 && '${inside.stdout}'.trim() == 'true';
    if (!isRepo) {
      changes = [];
      workspace.setGitStatus({});
      notifyListeners();
      return;
    }
    final ProcessResult top = await _git(['rev-parse', '--show-toplevel'], log: false);
    final String repoRoot = p.normalize('${top.stdout}'.trim());
    final ProcessResult r = await _git(['status', '--porcelain=v1', '-b', '-z', '--untracked-files=all'], log: false);
    final List<String> parts = '${r.stdout}'.split('\x00');
    final List<GitChange> list = [];
    for (int i = 0; i < parts.length; i++) {
      final String e = parts[i];
      if (e.isEmpty) continue;
      if (e.startsWith('## ')) {
        _parseBranch(e.substring(3));
        continue;
      }
      if (e.length < 4) continue;
      final String x = e[0], y = e[1];
      final String rel = e.substring(3);
      String? orig;
      if (x == 'R' || x == 'C') {
        orig = i + 1 < parts.length ? parts[++i] : null;
      }
      list.add(GitChange(p.normalize(p.join(repoRoot, rel)), x, y, origPath: orig));
    }
    changes = list;
    final Map<String, String> status = {};
    for (final GitChange c in list) {
      status[c.path] = c.untracked ? 'U' : (c.conflicted ? '!' : (c.work != ' ' ? c.work : c.index));
    }
    workspace.setGitStatus(status);
    notifyListeners();
  }

  void _parseBranch(String s) {
    // "main...origin/main [ahead 1, behind 2]" or "No commits yet on main"
    ahead = 0;
    behind = 0;
    upstream = null;
    if (s.startsWith('No commits yet on ')) {
      branch = s.substring('No commits yet on '.length);
      return;
    }
    if (s.startsWith('HEAD (no branch)')) {
      branch = 'HEAD (detached)';
      return;
    }
    final RegExpMatch? m = RegExp(r'^([^.\s]+(?:\.[^.\s]+)*?)(?:\.\.\.(\S+))?(?: \[(.*)\])?$').firstMatch(s);
    if (m == null) {
      branch = s;
      return;
    }
    branch = m.group(1) ?? s;
    upstream = m.group(2);
    final String info = m.group(3) ?? '';
    ahead = int.tryParse(RegExp(r'ahead (\d+)').firstMatch(info)?.group(1) ?? '') ?? 0;
    behind = int.tryParse(RegExp(r'behind (\d+)').firstMatch(info)?.group(1) ?? '') ?? 0;
  }

  Future<bool> _run(List<String> args) async {
    busy = true;
    lastError = null;
    notifyListeners();
    final ProcessResult r = await _git(args);
    busy = false;
    if (r.exitCode != 0) {
      lastError = '${r.stderr}'.trim().isEmpty ? '${r.stdout}'.trim() : '${r.stderr}'.trim();
    }
    await refresh();
    return r.exitCode == 0;
  }

  Future<bool> initRepo() => _run(['init']);
  Future<bool> stage(List<String> paths) => _run(['add', '--', ...paths]);
  Future<bool> stageAll() => _run(['add', '-A']);
  Future<bool> unstage(List<String> paths) => _run(['restore', '--staged', '--', ...paths]);
  Future<bool> unstageAll() => _run(['reset', '-q']);

  Future<bool> discard(GitChange c) async {
    if (c.untracked) {
      try {
        await File(c.path).delete();
      } catch (_) {}
      await refresh();
      return true;
    }
    return _run(['restore', '--', c.path]);
  }

  Future<bool> commit(String message, {bool amend = false, bool all = false}) async {
    if (message.trim().isEmpty && !amend) {
      lastError = 'Commit message is empty';
      notifyListeners();
      return false;
    }
    if (all && staged.isEmpty) await _git(['add', '-A']);
    return _run(['commit', if (amend) '--amend', if (amend && message.trim().isEmpty) '--no-edit' else ...['-m', message]]);
  }

  Future<bool> push() async {
    if (upstream == null) return _run(['push', '-u', 'origin', branch]);
    return _run(['push']);
  }

  Future<bool> pull() => _run(['pull', '--ff-only']);
  Future<bool> fetch() => _run(['fetch', '--all', '--prune']);
  Future<bool> sync() async => await pull() && await push();
  Future<bool> checkout(String b) => _run(['checkout', b]);
  Future<bool> createBranch(String b) => _run(['checkout', '-b', b]);
  Future<bool> stash() => _run(['stash', 'push', '-u']);
  Future<bool> stashPop() => _run(['stash', 'pop']);

  Future<void> loadBranches() async {
    final ProcessResult r = await _git(['branch', '--all', '--format=%(refname:short)'], log: false);
    branches = '${r.stdout}'.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty && !s.endsWith('/HEAD')).toList();
    notifyListeners();
  }

  Future<void> loadLog() async {
    final ProcessResult r = await _git(['log', '-n', '60', '--date=relative', '--pretty=format:%h\x1f%an\x1f%ad\x1f%s'], log: false);
    log = '${r.stdout}'
        .split('\n')
        .where((l) => l.contains('\x1f'))
        .map((l) {
          final List<String> f = l.split('\x1f');
          return GitCommitInfo(f[0], f[1], f[2], f.length > 3 ? f[3] : '');
        })
        .toList();
    notifyListeners();
  }

  /// Content of [path] at HEAD (empty for new files).
  Future<String> headContent(String path) async {
    final ProcessResult top = await _git(['rev-parse', '--show-toplevel'], log: false);
    final String rel = p.relative(path, from: p.normalize('${top.stdout}'.trim())).replaceAll('\\', '/');
    final ProcessResult r = await _git(['show', 'HEAD:$rel'], log: false);
    return r.exitCode == 0 ? '${r.stdout}' : '';
  }

  Future<String> diff(String path, {bool staged = false}) async {
    final ProcessResult r = await _git(['diff', if (staged) '--cached', '--', path], log: false);
    return '${r.stdout}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Decodes process output as UTF-8 regardless of the console code page.
class SystemEncodingUtf8 extends Encoding {
  const SystemEncodingUtf8();

  @override
  Converter<List<int>, String> get decoder => const Utf8Decoder(allowMalformed: true);

  @override
  Converter<String, List<int>> get encoder => const Utf8Encoder();

  @override
  String get name => 'utf-8';
}
