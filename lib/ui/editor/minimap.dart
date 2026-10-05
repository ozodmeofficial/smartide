import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../theme/ide_theme.dart';
import '../widgets.dart';

/// A lightweight code overview: each line is drawn as a bar whose length
/// follows the text, tinted by the dominant token type. Click or drag to
/// scroll.
class Minimap extends StatefulWidget {
  const Minimap({super.key, required this.controller, required this.scroll, required this.theme, required this.lineHeight, this.markers = const {}});

  final CodeLineEditingController controller;
  final ScrollController scroll;
  final IdeTheme theme;
  final double lineHeight;

  /// line index -> colour (diagnostics, search hits).
  final Map<int, Color> markers;

  @override
  State<Minimap> createState() => _MinimapState();
}

class _MinimapState extends State<Minimap> with SafeSetState {
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_tick);
    widget.scroll.addListener(_tick);
  }

  @override
  void didUpdateWidget(covariant Minimap old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_tick);
      widget.controller.addListener(_tick);
    }
    if (old.scroll != widget.scroll) {
      old.scroll.removeListener(_tick);
      widget.scroll.addListener(_tick);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_tick);
    widget.scroll.removeListener(_tick);
    super.dispose();
  }

  void _tick() => safeRebuild();

  void _jump(double dy, double height) {
    if (!widget.scroll.hasClients) return;
    final ScrollPosition pos = widget.scroll.position;
    final int lines = widget.controller.codeLines.length;
    final double scale = _scale(height, lines);
    final double contentLine = (dy / scale).clamp(0, lines.toDouble());
    final double target = contentLine * widget.lineHeight - pos.viewportDimension / 2;
    widget.scroll.jumpTo(target.clamp(0, pos.maxScrollExtent));
  }

  static const double _rowH = 2.6;

  double _scale(double height, int lines) => math.min(_rowH, height / math.max(lines, 1));

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: LayoutBuilder(builder: (context, box) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _jump(d.localPosition.dy, box.maxHeight),
          onVerticalDragUpdate: (d) => _jump(d.localPosition.dy, box.maxHeight),
          child: CustomPaint(
            size: Size(box.maxWidth, box.maxHeight),
            painter: _MinimapPainter(
              lines: widget.controller.codeLines,
              theme: widget.theme,
              scroll: widget.scroll,
              lineHeight: widget.lineHeight,
              hover: _hover,
              markers: widget.markers,
              cursorLine: widget.controller.selection.extentIndex,
              rowH: _rowH,
            ),
          ),
        );
      }),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.lines,
    required this.theme,
    required this.scroll,
    required this.lineHeight,
    required this.hover,
    required this.markers,
    required this.cursorLine,
    required this.rowH,
  });

  final CodeLines lines;
  final IdeTheme theme;
  final ScrollController scroll;
  final double lineHeight;
  final bool hover;
  final Map<int, Color> markers;
  final int cursorLine;
  final double rowH;

  static final RegExp _keyword = RegExp(r'^\s*(def|class|function|func|fn|public|private|static|import|from|package|using|#include|return|if|for|while|const|let|var|struct|impl|interface|type)\b');
  static final RegExp _comment = RegExp(r'^\s*(//|#|/\*|\*|--|<!--)');

  @override
  void paint(Canvas canvas, Size size) {
    final int count = lines.length;
    if (count == 0) return;
    final double scale = math.min(rowH, size.height / count);
    const double charW = 1.15;
    final Paint paint = Paint();
    final double viewportLines = scroll.hasClients ? scroll.position.viewportDimension / lineHeight : 0;
    final double offsetLines = scroll.hasClients ? scroll.offset / lineHeight : 0;

    // Viewport slider.
    if (scroll.hasClients) {
      paint.color = theme.text.withValues(alpha: hover ? 0.10 : 0.06);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, offsetLines * scale, size.width, math.max(viewportLines * scale, 12)), const Radius.circular(3)),
        paint,
      );
    }

    final int step = count > 6000 ? (count / 3000).ceil() : 1;
    for (int i = 0; i < count; i += step) {
      final String text = lines[i].text;
      if (text.trim().isEmpty) continue;
      final int indent = text.length - text.trimLeft().length;
      final double x = 6 + math.min(indent, 40) * charW;
      final double w = math.min(text.trimRight().length - indent, 90) * charW;
      if (w <= 0) continue;
      Color c;
      if (_comment.hasMatch(text)) {
        c = theme.palette.comment;
      } else if (_keyword.hasMatch(text)) {
        c = theme.palette.keyword;
      } else if (text.contains('"') || text.contains("'")) {
        c = theme.palette.string;
      } else {
        c = theme.text;
      }
      paint.color = c.withValues(alpha: 0.55);
      canvas.drawRect(Rect.fromLTWH(x, i * scale, math.min(w, size.width - x - 4), math.max(scale * 0.7, 1)), paint);
    }

    // Cursor line + markers on the right edge.
    paint.color = theme.accent.withValues(alpha: 0.9);
    canvas.drawRect(Rect.fromLTWH(0, cursorLine * scale, size.width, math.max(scale, 1.5)), paint..color = theme.accent.withValues(alpha: 0.35));
    markers.forEach((line, color) {
      paint.color = color;
      canvas.drawRect(Rect.fromLTWH(size.width - 4, line * scale - 1, 4, math.max(scale, 3)), paint);
    });
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter old) => true;
}
