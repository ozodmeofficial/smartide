import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/ide.dart';
import '../app/quick_pick.dart';
import '../theme/ide_theme.dart';
import 'widgets.dart';

/// Command palette / quick open / picker overlay.
class QuickPickOverlay extends StatefulWidget {
  const QuickPickOverlay({super.key, required this.request});

  final QuickPickRequest request;

  @override
  State<QuickPickOverlay> createState() => _QuickPickOverlayState();
}

class _QuickPickOverlayState extends State<QuickPickOverlay> {
  late final TextEditingController _input = TextEditingController(text: widget.request.initialValue);
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  List<QuickPickItem> _items = [];
  int _index = 0;
  Timer? _debounce;
  int _gen = 0;

  static const double _rowH = 30;

  @override
  void initState() {
    super.initState();
    _input.selection = TextSelection(baseOffset: 0, extentOffset: _input.text.length);
    _refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void didUpdateWidget(covariant QuickPickOverlay old) {
    super.didUpdateWidget(old);
    if (old.request != widget.request) {
      _input.text = widget.request.initialValue;
      _index = 0;
      _refresh();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final QuickPickRequest r = widget.request;
    final String q = _input.text;
    if (r.inputOnly) return;
    if (r.loader != null && q.startsWith('>')) {
      final Ide ide = context.read<Ide>();
      ide.closeQuickPick(cancelled: false);
      ide.showCommandPalette(q.substring(1));
      return;
    }
    final int gen = ++_gen;
    List<QuickPickItem> items;
    if (r.loader != null) {
      items = await r.loader!(q);
      if (gen != _gen || !mounted) return;
    } else if (q.trim().isEmpty) {
      items = r.items;
    } else {
      final List<(int, QuickPickItem)> scored = [];
      for (final QuickPickItem it in r.items) {
        int? s = fuzzyScore(it.label, q.trim());
        if (s == null && r.matchOnDescription && it.description != null) {
          final int? d = fuzzyScore(it.description!, q.trim());
          if (d != null) s = d - 200;
        }
        if (s != null) scored.add((s, it));
      }
      scored.sort((a, b) => b.$1.compareTo(a.$1));
      items = [for (final (int, QuickPickItem) e in scored) QuickPickItem(label: e.$2.label, description: e.$2.description, detail: e.$2.detail, icon: e.$2.icon, iconColor: e.$2.iconColor, badge: e.$2.badge, keybinding: e.$2.keybinding, value: e.$2.value)];
    }
    setState(() {
      _items = items;
      _index = 0;
    });
    _notifyActive();
  }

  void _notifyActive() {
    if (_items.isNotEmpty) widget.request.onActive?.call(_items[_index.clamp(0, _items.length - 1)]);
  }

  void _move(int delta) {
    if (_items.isEmpty) return;
    setState(() => _index = delta.abs() > 1 ? (_index + delta).clamp(0, _items.length - 1) : (_index + delta) % _items.length);
    final double top = _index * _rowH;
    if (_scroll.hasClients) {
      final double view = _scroll.position.viewportDimension;
      if (top < _scroll.offset) {
        _scroll.jumpTo(top);
      } else if (top + _rowH > _scroll.offset + view) {
        _scroll.jumpTo(top + _rowH - view);
      }
    }
    _notifyActive();
  }

  void _accept([int? i]) {
    final Ide ide = context.read<Ide>();
    final QuickPickRequest r = widget.request;
    final String q = _input.text;
    if (r.inputOnly) {
      ide.closeQuickPick(cancelled: false);
      r.onInput?.call(q);
      return;
    }
    if (_items.isEmpty) return;
    final QuickPickItem item = _items[(i ?? _index).clamp(0, _items.length - 1)];
    ide.closeQuickPick(cancelled: false);
    r.onAccept?.call(item, q);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (k == LogicalKeyboardKey.pageDown) {
      _move(10);
    } else if (k == LogicalKeyboardKey.pageUp) {
      _move(-10);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _accept();
    } else if (k == LogicalKeyboardKey.escape) {
      context.read<Ide>().closeQuickPick();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final QuickPickRequest r = widget.request;
    final String q = _input.text.trim();
    return Stack(children: [
      Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => context.read<Ide>().closeQuickPick())),
      Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 46),
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.96, end: 1),
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              builder: (context, v, child) => Opacity(opacity: ((v - 0.96) / 0.04).clamp(0, 1), child: Transform.scale(scale: v, alignment: Alignment.topCenter, child: child)),
              child: Container(
                width: 640,
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.borderStrong),
                  boxShadow: [BoxShadow(color: t.shadow, blurRadius: 40, offset: const Offset(0, 14))],
                ),
                padding: const EdgeInsets.all(6),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (r.title != null) Padding(padding: const EdgeInsets.fromLTRB(6, 2, 6, 6), child: Text(r.title!, style: uiText(t, size: 12, color: t.textMuted))),
                  Focus(
                    onKeyEvent: _onKey,
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      style: uiText(t, size: 14),
                      cursorColor: t.accent,
                      decoration: InputDecoration(
                        hintText: r.placeholder,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        prefixIcon: Icon(r.inputOnly ? Icons.keyboard_return_rounded : Icons.search_rounded, size: 17, color: t.textFaint),
                        prefixIconConstraints: const BoxConstraints(minWidth: 36),
                      ),
                      onChanged: (_) {
                        _debounce?.cancel();
                        _debounce = Timer(Duration(milliseconds: r.loader != null ? 70 : 0), _refresh);
                      },
                    ),
                  ),
                  if (!r.inputOnly) ...[
                    const SizedBox(height: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: _rowH * 13),
                      child: _items.isEmpty
                          ? Padding(padding: const EdgeInsets.all(12), child: Text('No matching results', style: uiText(t, color: t.textFaint)))
                          : ListView.builder(
                              controller: _scroll,
                              shrinkWrap: true,
                              itemCount: _items.length,
                              itemExtent: _rowH,
                              itemBuilder: (context, i) => _row(t, _items[i], i == _index, q, i),
                            ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _row(IdeTheme t, QuickPickItem it, bool sel, String q, int i) {
    final List<int> hits = fuzzyIndices(it.label, q);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (_) {
        if (_index != i) {
          setState(() => _index = i);
          _notifyActive();
        }
      },
      child: GestureDetector(
        onTap: () => _accept(i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: sel ? t.accentSoft : null, borderRadius: BorderRadius.circular(7)),
          child: Row(children: [
            if (it.badge != null) ...[LanguageBadge(badge: it.badge!, color: it.iconColor ?? t.accent, size: 16), const SizedBox(width: 10)]
            else if (it.icon != null) ...[Icon(it.icon, size: 15, color: it.iconColor ?? t.textMuted), const SizedBox(width: 10)],
            Flexible(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(style: uiText(t, size: 13.5), children: [
                  for (int c = 0; c < it.label.length; c++)
                    TextSpan(text: it.label[c], style: hits.contains(c) ? TextStyle(color: t.accent, fontWeight: FontWeight.w700) : null),
                ]),
              ),
            ),
            if (it.description != null && it.description!.isNotEmpty) ...[
              const SizedBox(width: 10),
              Flexible(child: Text(it.description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(t, size: 12, color: t.textFaint))),
            ],
            if (it.detail != null) ...[const SizedBox(width: 8), Text(it.detail!, style: uiText(t, size: 11, color: t.textFaint))],
            const Spacer(),
            if (it.keybinding != null) Kbd(it.keybinding!, small: true),
          ]),
        ),
      ),
    );
  }
}
