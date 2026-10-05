import 'package:flutter/foundation.dart';

/// Named log channels shown in the Output panel.
class OutputService extends ChangeNotifier {
  final Map<String, List<String>> _channels = {'SmartIDE': []};
  String selected = 'SmartIDE';

  List<String> get channelNames => _channels.keys.toList();
  List<String> lines(String channel) => _channels[channel] ?? const [];

  void append(String channel, String text) {
    final List<String> list = _channels.putIfAbsent(channel, () => []);
    final String ts = DateTime.now().toIso8601String().substring(11, 19);
    for (final String line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      list.add('[$ts] $line');
    }
    if (list.length > 4000) list.removeRange(0, list.length - 4000);
    notifyListeners();
  }

  void clear(String channel) {
    _channels[channel]?.clear();
    notifyListeners();
  }

  void select(String channel) {
    selected = channel;
    notifyListeners();
  }
}

enum ToastKind { info, success, warning, error }

class ToastAction {
  const ToastAction(this.label, this.onPressed);

  final String label;
  final VoidCallback onPressed;
}

class Toast {
  Toast(this.id, this.message, this.kind, this.actions, {this.detail, this.progress = false});

  final int id;
  final String message;
  final String? detail;
  final ToastKind kind;
  final List<ToastAction> actions;
  final bool progress;
}

/// Non-blocking notifications shown in the bottom-right corner.
class NotificationService extends ChangeNotifier {
  final List<Toast> toasts = [];
  int _next = 0;

  int show(String message, {ToastKind kind = ToastKind.info, String? detail, List<ToastAction> actions = const [], Duration? duration, bool progress = false}) {
    final Toast t = Toast(_next++, message, kind, actions, detail: detail, progress: progress);
    toasts.add(t);
    if (toasts.length > 4) toasts.removeAt(0);
    notifyListeners();
    final Duration d = duration ?? (actions.isEmpty && !progress ? const Duration(seconds: 5) : const Duration(seconds: 14));
    Future<void>.delayed(d, () => dismiss(t.id));
    return t.id;
  }

  void info(String m, {String? detail}) => show(m, detail: detail);
  void success(String m, {String? detail}) => show(m, kind: ToastKind.success, detail: detail);
  void warn(String m, {String? detail, List<ToastAction> actions = const []}) => show(m, kind: ToastKind.warning, detail: detail, actions: actions);
  void error(String m, {String? detail, List<ToastAction> actions = const []}) => show(m, kind: ToastKind.error, detail: detail, actions: actions);

  void dismiss(int id) {
    toasts.removeWhere((t) => t.id == id);
    notifyListeners();
  }
}
