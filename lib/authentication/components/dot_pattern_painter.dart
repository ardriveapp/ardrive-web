import 'package:flutter/material.dart';

class DotPatternPainter extends CustomPainter {
  final Color dotColor;

  DotPatternPainter({required this.dotColor});

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = const Color(0xff424242)
      ..style = PaintingStyle.fill;

    for (int y = 0; y < size.height; y += 5) {
      for (int x = 0; x < size.width; x += 5) {
        canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 2, 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
