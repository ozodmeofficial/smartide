import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The SmartIDE mark: a warm rounded tile with a code chevron and a spark.
class SmartIdeLogo extends StatelessWidget {
  const SmartIdeLogo({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: const LogoPainter());
}

class LogoPainter extends CustomPainter {
  const LogoPainter();

  static const Color terracotta = Color(0xFFD97757);
  static const Color ember = Color(0xFFC2553A);
  static const Color sand = Color(0xFFF2B283);

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final RRect tile = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.26));
    canvas.drawRRect(
      tile,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [sand, terracotta, ember],
          stops: [0.0, 0.5, 1.0],
        ).createShader(Offset.zero & size),
    );
    // Subtle inner highlight.
    canvas.drawRRect(
      tile.deflate(s * 0.02),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.025
        ..color = Colors.white.withValues(alpha: 0.18),
    );

    final Paint stroke = Paint()
      ..color = const Color(0xFFFFFBF5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.105
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Chevron ">"
    final Path chevron = Path()
      ..moveTo(s * 0.24, s * 0.32)
      ..lineTo(s * 0.43, s * 0.5)
      ..lineTo(s * 0.24, s * 0.68);
    canvas.drawPath(chevron, stroke);

    // Cursor underscore
    canvas.drawLine(Offset(s * 0.5, s * 0.69), Offset(s * 0.66, s * 0.69), stroke);

    // Four-point spark (top right).
    final Offset c = Offset(s * 0.69, s * 0.33);
    final double r = s * 0.15;
    final Path spark = Path();
    for (int i = 0; i < 4; i++) {
      final double a = i * math.pi / 2 - math.pi / 2;
      final double b = a + math.pi / 4;
      final Offset tip = c + Offset(math.cos(a), math.sin(a)) * r;
      final Offset waist = c + Offset(math.cos(b), math.sin(b)) * r * 0.28;
      if (i == 0) {
        spark.moveTo(tip.dx, tip.dy);
      } else {
        spark.lineTo(tip.dx, tip.dy);
      }
      spark.lineTo(waist.dx, waist.dy);
    }
    spark.close();
    canvas.drawPath(spark, Paint()..color = const Color(0xFFFFFBF5));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
