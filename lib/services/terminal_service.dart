import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart';

import '../core/toolchain.dart';

/// A shell that can be started in the integrated terminal.
class ShellProfile {
  const ShellProfile({required this.id, required this.name, required this.executable, this.args = const [], required this.icon});

  final String id;
  final String name;
  final String executable;
  final List<String> args;

  /// Short glyph shown in the terminal tab ("PS", ">_", "$").
  final String icon;
}

class TerminalSession {
  TerminalSession({required this.id, required this.title, required this.profile, this.isTask = false})
      : terminal = Terminal(maxLines: 10000, platform: Platform.isWindows ? TerminalTargetPlatform.windows : TerminalTargetPlatform.linux),
        controller = TerminalController();

  final int id;
  String title;
  final ShellProfile profile;
  final bool isTask;
  final Terminal terminal;
  final TerminalController controller;
  Pty? pty;
  bool exited = false;
  int? exitCode;
  DateTime started = DateTime.now();

  void write(String text) {
    if (exited || pty == null) return;
    pty!.write(const Utf8Encoder().convert(text));
  }

  void kill() {
    final Pty? proc = pty;
    if (proc == null || exited) return;
    if (Platform.isWindows) {
      // Kill the whole process tree (e.g. cmd -> python).
      Process.run('taskkill', ['/PID', '${proc.pid}', '/T', '/F']).catchError((_) => ProcessResult(0, 1, '', ''));
    } else {
      proc.kill();
    }
  }
}

/// Manages integrated terminal sessions (PowerShell, CMD, Git Bash, WSL, ...).
class TerminalService extends ChangeNotifier {
  final List<TerminalSession> sessions = [];
  final List<ShellProfile> profiles = [];
  int activeIndex = -1;
  int _nextId = 1;
  String defaultProfileId = 'auto';

  /// Working directory for new terminals (the open folder).
  String? cwd;

  TerminalSession? get active => activeIndex >= 0 && activeIndex < sessions.length ? sessions[activeIndex] : null;

  Future<void> detectProfiles() async {
    profiles.clear();
    if (Platform.isWindows) {
      final String sysRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final String? pwsh = await Toolchain.which('pwsh');
      if (pwsh != null) {
        profiles.add(ShellProfile(id: 'pwsh', name: 'PowerShell 7', executable: pwsh, args: ['-NoLogo'], icon: 'PS'));
      }
      final String winPs = p.join(sysRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
      if (await File(winPs).exists()) {
        profiles.add(ShellProfile(id: 'powershell', name: 'Windows PowerShell', executable: winPs, args: ['-NoLogo'], icon: 'PS'));
      }
      final String cmd = Platform.environment['ComSpec'] ?? p.join(sysRoot, 'System32', 'cmd.exe');
      profiles.add(ShellProfile(id: 'cmd', name: 'Command Prompt', executable: cmd, icon: '>_'));
      for (final String base in [
        Platform.environment['ProgramFiles'] ?? r'C:\Program Files',
        Platform.environment['ProgramW6432'] ?? r'C:\Program Files',
        p.join(Platform.environment['LOCALAPPDATA'] ?? '', 'Programs'),
      ]) {
        final String bash = p.join(base, 'Git', 'bin', 'bash.exe');
        if (await File(bash).exists()) {
          profiles.add(ShellProfile(id: 'gitbash', name: 'Git Bash', executable: bash, args: ['--login', '-i'], icon: r'$'));
          break;
        }
      }
      final String wsl = p.join(sysRoot, 'System32', 'wsl.exe');
      if (await File(wsl).exists()) {
        profiles.add(ShellProfile(id: 'wsl', name: 'WSL', executable: wsl, icon: '🐧'));
      }
    } else {
      final String userShell = Platform.environment['SHELL'] ?? '/bin/bash';
      profiles.add(ShellProfile(id: 'default', name: p.basename(userShell), executable: userShell, args: ['-l'], icon: r'$'));
      for (final String sh in ['bash', 'zsh', 'fish', 'pwsh']) {
        final String? path = await Toolchain.which(sh);
        if (path != null && path != userShell) {
          profiles.add(ShellProfile(id: sh, name: sh, executable: path, args: sh == 'pwsh' ? ['-NoLogo'] : ['-l'], icon: sh == 'pwsh' ? 'PS' : r'$'));
        }
      }
    }
    notifyListeners();
  }

  ShellProfile get defaultProfile {
    if (profiles.isEmpty) {
      return Platform.isWindows
          ? const ShellProfile(id: 'cmd', name: 'Command Prompt', executable: 'cmd.exe', icon: '>_')
          : const ShellProfile(id: 'sh', name: 'sh', executable: '/bin/sh', icon: r'$');
    }
    return profiles.where((pr) => pr.id == defaultProfileId).firstOrNull ?? profiles.first;
  }

  static Map<String, String> _environment() => {
        ...Platform.environment,
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
        'TERM_PROGRAM': 'SmartIDE',
        'PYTHONIOENCODING': 'utf-8',
        'PYTHONUTF8': '1',
        if (!Platform.isWindows) 'LANG': Platform.environment['LANG'] ?? 'en_US.UTF-8',
      };

  static String _quote(String exe) => exe.contains(' ') && !exe.startsWith('"') ? '"$exe"' : exe;

  /// Opens a new interactive shell.
  TerminalSession create({ShellProfile? profile, String? workingDirectory}) {
    final ShellProfile pr = profile ?? defaultProfile;
    final TerminalSession s = TerminalSession(id: _nextId++, title: pr.name, profile: pr);
    _start(s, pr.executable, pr.args, workingDirectory ?? cwd);
    sessions.add(s);
    activeIndex = sessions.length - 1;
    notifyListeners();
    return s;
  }

  /// Runs [command] in a dedicated task terminal and reports the exit code.
  TerminalSession runTask(String title, String command, {String? workingDirectory, void Function(int code)? onExit}) {
    // Reuse a finished task terminal with the same title to avoid clutter.
    final int reuse = sessions.indexWhere((s) => s.isTask && s.title == title && s.exited);
    if (reuse >= 0) {
      sessions.removeAt(reuse);
      if (activeIndex >= sessions.length) activeIndex = sessions.length - 1;
    }
    final ShellProfile pr = Platform.isWindows
        ? ShellProfile(id: 'task', name: title, executable: Platform.environment['ComSpec'] ?? 'cmd.exe', icon: '▶')
        : const ShellProfile(id: 'task', name: 'task', executable: '/bin/bash', icon: '▶');
    final TerminalSession s = TerminalSession(id: _nextId++, title: title, profile: pr, isTask: true);
    s.terminal.write('\x1b[38;5;173m▶ $command\x1b[0m\r\n\r\n');
    final List<String> args = Platform.isWindows
        ? ['/d', '/s', '/c', '"chcp 65001 >nul & $command"']
        : ['-lc', command];
    _start(s, pr.executable, args, workingDirectory ?? cwd, onExit: onExit);
    sessions.add(s);
    activeIndex = sessions.length - 1;
    notifyListeners();
    return s;
  }

  void _start(TerminalSession s, String exe, List<String> args, String? dir, {void Function(int code)? onExit}) {
    try {
      final Pty pty = Pty.start(
        Platform.isWindows ? _quote(exe) : exe,
        arguments: args,
        workingDirectory: dir != null && Directory(dir).existsSync() ? dir : null,
        environment: _environment(),
        columns: s.terminal.viewWidth,
        rows: s.terminal.viewHeight,
      );
      s.pty = pty;
      pty.output.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen(s.terminal.write);
      pty.exitCode.then((code) {
        s.exited = true;
        s.exitCode = code;
        // -999999: exit status unknown (child reaped by another waiter).
        final bool unknown = code == -999999;
        final String color = code == 0 || unknown ? '32' : '31';
        final String codeText = unknown ? '' : ' with exit code $code';
        final String msg = s.isTask
            ? '\r\n\x1b[${color}m● Process finished$codeText\x1b[0m  \x1b[2m(${DateTime.now().difference(s.started).inMilliseconds} ms)\x1b[0m\r\n'
            : '\r\n\x1b[2m[Process exited$codeText]\x1b[0m\r\n';
        s.terminal.write(msg);
        onExit?.call(unknown ? 0 : code);
        notifyListeners();
      });
      s.terminal.onOutput = (data) => s.write(data);
      s.terminal.onResize = (w, h, pw, ph) {
        if (!s.exited) pty.resize(h, w);
      };
      s.terminal.onTitleChange = (t) {
        if (!s.isTask && t.trim().isNotEmpty) {
          s.title = t.length > 40 ? '…${t.substring(t.length - 39)}' : t;
          notifyListeners();
        }
      };
    } catch (e) {
      s.exited = true;
      s.terminal.write('\x1b[31mFailed to start "$exe": $e\x1b[0m\r\n');
    }
  }

  void setActive(int i) {
    if (i < 0 || i >= sessions.length) return;
    activeIndex = i;
    notifyListeners();
  }

  void close(TerminalSession s) {
    s.kill();
    final int i = sessions.indexOf(s);
    if (i < 0) return;
    sessions.removeAt(i);
    if (activeIndex >= sessions.length) activeIndex = sessions.length - 1;
    notifyListeners();
  }

  void closeAll() {
    for (final TerminalSession s in sessions) {
      s.kill();
    }
    sessions.clear();
    activeIndex = -1;
    notifyListeners();
  }

  /// Sends text to the active terminal (creating one if needed).
  void sendToActive(String text, {bool execute = true}) {
    TerminalSession s = active ?? create();
    if (s.exited || s.isTask) s = create();
    s.write(execute ? '$text\r' : text);
  }

  void clearActive() {
    final TerminalSession? s = active;
    if (s == null) return;
    s.terminal.buffer.clear();
    s.terminal.buffer.setCursor(0, 0);
    s.terminal.notifyListeners();
    if (!s.isTask) s.write(Platform.isWindows ? '\r' : '\x0c');
  }

  @override
  void dispose() {
    closeAll();
    super.dispose();
  }
}
