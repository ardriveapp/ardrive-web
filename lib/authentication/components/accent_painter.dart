import 'package:flutter/material.dart';

class AccentPainter extends CustomPainter {
  double lineHeight;

  AccentPainter({required this.lineHeight});

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = Colors.red.shade500
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(3, 8), 2.5, paint);
    var rect = Rect.fromLTWH(2.5, 8, 1, lineHeight);
    paint = Paint()
      ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.red.shade500,
            Colors.red.shade500,
            Colors.red.shade500.withAlpha(0)
          ]).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
