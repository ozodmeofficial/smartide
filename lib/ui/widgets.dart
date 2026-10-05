import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/ide.dart';
import '../core/languages.dart';
import '../theme/ide_theme.dart';

/// UI font stack: Segoe UI Variable on Windows 11, Segoe UI on Windows 10.
const String kUiFont = 'Segoe UI Variable Text';
const List<String> kUiFontFallback = ['Segoe UI', 'Inter', 'Ubuntu', 'Cantarell', 'Noto Sans', 'sans-serif'];

/// Serif display font for headings (Claude-like warmth).
const String kSerifFont = 'Georgia';
const List<String> kSerifFallback = ['Cambria', 'Times New Roman', 'Noto Serif', 'serif'];

extension IdeContext on BuildContext {
  IdeTheme get t => watch<Ide>().effectiveTheme;
  IdeTheme get tRead => read<Ide>().effectiveTheme;
  Ide get ide => read<Ide>();
}

TextStyle uiText(IdeTheme t, {double size = 13, Color? color, FontWeight? weight, double? height}) => TextStyle(
      fontFamily: kUiFont,
      fontFamilyFallback: kUiFontFallback,
      fontSize: size,
      color: color ?? t.text,
      fontWeight: weight,
      height: height,
    );

TextStyle serifText(IdeTheme t, {double size = 28, Color? color, FontWeight weight = FontWeight.w400}) => TextStyle(
      fontFamily: kSerifFont,
      fontFamilyFallback: kSerifFallback,
      fontSize: size,
      color: color ?? t.text,
      fontWeight: weight,
      letterSpacing: -0.3,
    );

/// A rectangle that highlights on hover and reacts to taps.
class HoverBox extends StatefulWidget {
  const HoverBox({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapDown,
    this.radius = 6,
    this.padding,
    this.selected = false,
    this.selectedColor,
    this.hoverColor,
    this.cursor = SystemMouseCursors.click,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(TapDownDetails d)? onSecondaryTapDown;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool selected;
  final Color? selectedColor;
  final Color? hoverColor;
  final MouseCursor cursor;
  final String? tooltip;

  @override
  State<HoverBox> createState() => _HoverBoxState();
}

class _HoverBoxState extends State<HoverBox> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Color? bg = widget.selected ? (widget.selectedColor ?? t.accentSoft) : (_hover ? (widget.hoverColor ?? t.hover) : null);
    Widget box = MouseRegion(
      cursor: widget.onTap == null && widget.onDoubleTap == null ? MouseCursor.defer : widget.cursor,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: widget.padding,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(widget.radius)),
          child: widget.child,
        ),
      ),
    );
    if (widget.tooltip != null) box = Tooltip(message: widget.tooltip!, child: box);
    return box;
  }
}

/// Small square icon button used in toolbars.
class IconBtn extends StatelessWidget {
  const IconBtn({super.key, required this.icon, this.onTap, this.tooltip, this.size = 16, this.color, this.active = false, this.box = 26});

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double box;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return HoverBox(
      onTap: onTap,
      tooltip: tooltip,
      selected: active,
      radius: 6,
      child: SizedBox(
        width: box,
        height: box,
        child: Icon(icon, size: size, color: onTap == null ? t.textFaint : (color ?? (active ? t.accent : t.textMuted))),
      ),
    );
  }
}

/// Coloured language badge used as a file icon.
class FileBadge extends StatelessWidget {
  const FileBadge({super.key, required this.path, this.size = 16, this.isDir = false, this.open = false});

  final String path;
  final double size;
  final bool isDir;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    if (isDir) {
      return Icon(open ? Icons.folder_open_rounded : Icons.folder_rounded, size: size + 1, color: t.accent.withValues(alpha: 0.85));
    }
    final LanguageDef l = languageForPath(path);
    return LanguageBadge(badge: l.badge, color: l.color, size: size);
  }
}

class LanguageBadge extends StatelessWidget {
  const LanguageBadge({super.key, required this.badge, required this.color, this.size = 16});

  final String badge;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bool dark = context.t.isDark;
    // Very dark brand colours (e.g. Lua navy) need lifting on dark themes.
    final Color c = dark && color.computeLuminance() < 0.06 ? IdeTheme.shift(color, 0.35) : color;
    final double fs = badge.length >= 3 ? size * 0.42 : size * 0.52;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: dark ? 0.2 : 0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(
        badge,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800, color: c, height: 1, fontFamily: 'JetBrains Mono', letterSpacing: -0.4),
      ),
    );
  }
}

/// Keyboard key cap, e.g. for shortcuts in menus and the welcome page.
class Kbd extends StatelessWidget {
  const Kbd(this.label, {super.key, this.small = false});

  final String label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final List<String> parts = label.split(' ');
    return Wrap(
      spacing: 3,
      children: [
        for (final String chord in parts)
          Container(
            padding: EdgeInsets.symmetric(horizontal: small ? 4 : 6, vertical: small ? 1 : 2),
            decoration: BoxDecoration(
              color: t.hover,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: t.border),
            ),
            child: Text(chord, style: uiText(t, size: small ? 10.5 : 11.5, color: t.textMuted)),
          ),
      ],
    );
  }
}

/// Draggable divider used to resize panes.
class Splitter extends StatefulWidget {
  const Splitter({super.key, required this.axis, required this.onDrag, this.onEnd, this.thickness = 6});

  /// Axis.horizontal => vertical bar resizing widths.
  final Axis axis;
  final ValueChanged<double> onDrag;
  final VoidCallback? onEnd;
  final double thickness;

  @override
  State<Splitter> createState() => _SplitterState();
}

class _SplitterState extends State<Splitter> {
  bool _hover = false;
  bool _drag = false;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final bool h = widget.axis == Axis.horizontal;
    return MouseRegion(
      cursor: h ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: h ? (_) => setState(() => _drag = true) : null,
        onHorizontalDragUpdate: h ? (d) => widget.onDrag(d.delta.dx) : null,
        onHorizontalDragEnd: h
            ? (_) {
                setState(() => _drag = false);
                widget.onEnd?.call();
              }
            : null,
        onVerticalDragStart: !h ? (_) => setState(() => _drag = true) : null,
        onVerticalDragUpdate: !h ? (d) => widget.onDrag(d.delta.dy) : null,
        onVerticalDragEnd: !h
            ? (_) {
                setState(() => _drag = false);
                widget.onEnd?.call();
              }
            : null,
        child: SizedBox(
          width: h ? widget.thickness : double.infinity,
          height: h ? double.infinity : widget.thickness,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: h ? 2 : double.infinity,
              height: h ? double.infinity : 2,
              color: _hover || _drag ? t.accent.withValues(alpha: 0.7) : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}

/// Section title in side bar views ("EXPLORER", "OPEN EDITORS").
class PaneHeader extends StatelessWidget {
  const PaneHeader({super.key, required this.title, this.actions = const [], this.onTap, this.expanded});

  final String title;
  final List<Widget> actions;
  final VoidCallback? onTap;
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            const SizedBox(width: 6),
            if (expanded != null)
              Icon(expanded! ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded, size: 16, color: t.textMuted),
            const SizedBox(width: 4),
            Expanded(
              child: Text(title.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: uiText(t, size: 11, weight: FontWeight.w600, color: t.textMuted).copyWith(letterSpacing: 0.8)),
            ),
            ...actions,
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

/// Primary (accent) button.
class AccentButton extends StatelessWidget {
  const AccentButton({super.key, required this.label, this.onTap, this.icon, this.subtle = false, this.dense = false});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool subtle;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    final Color bg = subtle ? t.hover : t.accent;
    final Color fg = subtle ? t.text : t.onAccent;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: HoverBox(
        onTap: onTap,
        radius: 8,
        hoverColor: subtle ? t.hover.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14, vertical: dense ? 5 : 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: subtle ? Border.all(color: t.border) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 6)],
              Text(label, style: uiText(t, size: dense ? 12 : 13, color: fg, weight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Context menu helper.
class MenuEntry {
  const MenuEntry(this.label, {this.onTap, this.shortcut, this.icon, this.divider = false, this.danger = false, this.enabled = true});

  const MenuEntry.divider()
      : label = '',
        onTap = null,
        shortcut = null,
        icon = null,
        divider = true,
        danger = false,
        enabled = true;

  final String label;
  final VoidCallback? onTap;
  final String? shortcut;
  final IconData? icon;
  final bool divider;
  final bool danger;
  final bool enabled;
}

Future<void> showContextMenu(BuildContext context, Offset position, List<MenuEntry> entries) async {
  final IdeTheme t = context.tRead;
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  void close() {
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) {
      final Size screen = MediaQuery.of(ctx).size;
      const double w = 260;
      final double h = entries.fold(8.0, (s, e) => s + (e.divider ? 9 : 30));
      final double left = (position.dx + w > screen.width) ? screen.width - w - 8 : position.dx;
      final double top = (position.dy + h > screen.height) ? (screen.height - h - 8).clamp(0, screen.height) : position.dy;
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: close,
              onSecondaryTap: close,
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: _MenuCard(theme: t, width: w, entries: entries, onClose: close),
          ),
        ],
      );
    },
  );
  overlay.insert(entry);
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.theme, required this.width, required this.entries, required this.onClose});

  final IdeTheme theme;
  final double width;
  final List<MenuEntry> entries;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = theme;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.border),
          boxShadow: [BoxShadow(color: t.shadow, blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final MenuEntry e in entries)
              if (e.divider)
                Padding(padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6), child: Container(height: 1, color: t.border))
              else
                _MenuRow(theme: t, entry: e, onClose: onClose),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({required this.theme, required this.entry, required this.onClose});

  final IdeTheme theme;
  final MenuEntry entry;
  final VoidCallback onClose;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = widget.theme;
    final MenuEntry e = widget.entry;
    final bool enabled = e.enabled && e.onTap != null;
    final Color fg = !enabled ? t.textFaint : (_hover ? t.onAccent : (e.danger ? t.error : t.text));
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = enabled),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled
            ? () {
                widget.onClose();
                e.onTap!();
              }
            : null,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: _hover ? t.accent : null, borderRadius: BorderRadius.circular(6)),
          child: Row(
            children: [
              SizedBox(width: 22, child: e.icon == null ? null : Icon(e.icon, size: 15, color: fg)),
              Expanded(child: Text(e.label, style: uiText(t, size: 13, color: fg), overflow: TextOverflow.ellipsis)),
              if (e.shortcut != null) Text(e.shortcut!, style: uiText(t, size: 11.5, color: _hover ? t.onAccent.withValues(alpha: 0.8) : t.textFaint)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps [child] in a rounded "card" surface (editor, panel).
class Card2 extends StatelessWidget {
  const Card2({super.key, required this.child, this.color, this.radius = 10});

  final Widget child;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? t.editorBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: t.border),
      ),
      child: child,
    );
  }
}

/// Text field with IDE styling.
class IdeTextField extends StatelessWidget {
  const IdeTextField({
    super.key,
    this.controller,
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.prefix,
    this.suffix,
    this.obscure = false,
    this.mono = false,
    this.dense = true,
  });

  final TextEditingController? controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final Widget? prefix;
  final Widget? suffix;
  final bool obscure;
  final bool mono;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      maxLines: obscure ? 1 : maxLines,
      minLines: minLines,
      obscureText: obscure,
      cursorColor: t.accent,
      cursorWidth: 1.6,
      style: mono ? TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12.5, color: t.text) : uiText(t, size: 13),
      decoration: InputDecoration(
        hintText: hint,
        isDense: dense,
        prefixIcon: prefix,
        prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 20),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 20),
      ),
    );
  }
}

/// Toggle used in search inputs ("Aa", ".*", "ab").
class ToggleGlyph extends StatelessWidget {
  const ToggleGlyph({super.key, required this.label, required this.value, required this.onChanged, this.tooltip});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final IdeTheme t = context.t;
    return HoverBox(
      onTap: () => onChanged(!value),
      tooltip: tooltip,
      radius: 4,
      selected: value,
      child: Container(
        width: 22,
        height: 20,
        alignment: Alignment.center,
        decoration: value ? BoxDecoration(border: Border.all(color: t.accent), borderRadius: BorderRadius.circular(4)) : null,
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: value ? t.accent : t.textMuted, fontFamily: 'JetBrains Mono')),
      ),
    );
  }
}

/// Copies [text] to the clipboard and shows a toast.
void copyToClipboard(BuildContext context, String text, {String message = 'Copied to clipboard'}) {
  Clipboard.setData(ClipboardData(text: text));
  context.ide.notifications.success(message);
}

/// Calls `setState` safely even when [listenable] notifies in the middle of
/// a build or layout (re_editor controllers do this while attaching).
mixin SafeSetState<T extends StatefulWidget> on State<T> {
  bool _scheduled = false;

  void safeRebuild() {
    if (!mounted) return;
    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
      setState(() {});
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) setState(() {});
    });
  }
}

/// [ListenableBuilder] that never rebuilds during a frame.
class SafeListenableBuilder extends StatefulWidget {
  const SafeListenableBuilder({super.key, required this.listenable, required this.builder});

  final Listenable listenable;
  final WidgetBuilder builder;

  @override
  State<SafeListenableBuilder> createState() => _SafeListenableBuilderState();
}

class _SafeListenableBuilderState extends State<SafeListenableBuilder> with SafeSetState {
  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(safeRebuild);
  }

  @override
  void didUpdateWidget(covariant SafeListenableBuilder old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(safeRebuild);
      widget.listenable.addListener(safeRebuild);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(safeRebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
