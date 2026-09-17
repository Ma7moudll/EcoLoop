import 'dart:math' as math;

import 'package:flutter/material.dart';

/// EcoLoop brand mark — a circular "loop" arrow drawn as a vector so it needs
/// no image asset. Rendered green by default; tint via [color].
class EcoLoopMark extends StatelessWidget {
  final double size;
  final Color color;

  const EcoLoopMark({super.key, this.size = 32, this.color = Colors.green});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _LoopPainter(color: color, strokeWidth: size * 0.13),
    );
  }
}

class _LoopPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const _LoopPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - strokeWidth;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: radius,
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Almost a full circle, leaving a gap for the arrowhead.
    const start = -0.35 * math.pi;
    const sweep = 1.72 * math.pi;
    canvas.drawArc(rect, start, sweep, false, paint);

    // Arrowhead at the end of the arc.
    final endAngle = start + sweep;
    final tip = rect.center +
        Offset(math.cos(endAngle) * radius, math.sin(endAngle) * radius);
    final back = endAngle - 0.42;
    final ah = strokeWidth * 1.5;
    final p1 = tip +
        Offset(math.cos(back) * ah, math.sin(back) * ah);
    final p2 = tip +
        Offset(math.cos(back + 0.84) * ah, math.sin(back + 0.84) * ah);
    final arrow = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      arrow,
    );
  }

  @override
  bool shouldRepaint(covariant _LoopPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}
