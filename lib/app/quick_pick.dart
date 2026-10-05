import 'package:flutter/widgets.dart';

class QuickPickItem {
  const QuickPickItem({
    required this.label,
    this.description,
    this.detail,
    this.icon,
    this.iconColor,
    this.badge,
    this.keybinding,
    this.value,
    this.separatorAbove,
  });

  final String label;
  final String? description;
  final String? detail;
  final IconData? icon;
  final Color? iconColor;

  /// Language badge for file items (e.g. "py").
  final String? badge;
  final String? keybinding;
  final Object? value;

  /// Group header shown above this item ("recently used", "other commands").
  final String? separatorAbove;
}

/// Describes a quick pick overlay (command palette, quick open, pickers).
class QuickPickRequest {
  QuickPickRequest({
    required this.placeholder,
    this.items = const [],
    this.loader,
    this.onAccept,
    this.onActive,
    this.onCancel,
    this.onInput,
    this.initialValue = '',
    this.title,
    this.matchOnDescription = true,
    this.inputOnly = false,
    this.validate,
  });

  final String placeholder;
  final String? title;
  final List<QuickPickItem> items;

  /// Optional dynamic items depending on the typed text (quick open).
  final Future<List<QuickPickItem>> Function(String query)? loader;
  final void Function(QuickPickItem item, String query)? onAccept;
  final void Function(QuickPickItem item)? onActive;
  final VoidCallback? onCancel;

  /// For input boxes: called when Enter is pressed with the raw text.
  final void Function(String text)? onInput;
  final String initialValue;
  final bool matchOnDescription;
  final bool inputOnly;
  final String? Function(String text)? validate;
}

/// Fuzzy matching with a score; returns null if [query] does not match.
/// Consecutive and word-start matches score higher (like VS Code).
int? fuzzyScore(String text, String query) {
  if (query.isEmpty) return 0;
  final String t = text.toLowerCase();
  final String q = query.toLowerCase();
  final int direct = t.indexOf(q);
  if (direct >= 0) return 1000 - direct * 2 - (t.length - q.length) ~/ 4 + (direct == 0 ? 300 : 0);
  int ti = 0;
  int score = 0;
  int streak = 0;
  for (int qi = 0; qi < q.length; qi++) {
    final int c = q.codeUnitAt(qi);
    if (c == 0x20) continue;
    bool found = false;
    while (ti < t.length) {
      if (t.codeUnitAt(ti) == c) {
        final bool wordStart = ti == 0 || ' /\\_-.'.contains(t[ti - 1]) || (text[ti].toUpperCase() == text[ti] && text[ti].toLowerCase() != text[ti]);
        streak++;
        score += 10 + streak * 5 + (wordStart ? 25 : 0);
        ti++;
        found = true;
        break;
      }
      streak = 0;
      ti++;
    }
    if (!found) return null;
  }
  return score - t.length ~/ 3;
}

/// Indices of characters in [text] matched by [query] (for highlighting).
List<int> fuzzyIndices(String text, String query) {
  if (query.isEmpty) return const [];
  final String t = text.toLowerCase();
  final String q = query.toLowerCase();
  final int direct = t.indexOf(q);
  if (direct >= 0) return List.generate(q.length, (i) => direct + i);
  final List<int> out = [];
  int ti = 0;
  for (int qi = 0; qi < q.length; qi++) {
    while (ti < t.length && t.codeUnitAt(ti) != q.codeUnitAt(qi)) {
      ti++;
    }
    if (ti >= t.length) return const [];
    out.add(ti++);
  }
  return out;
}
