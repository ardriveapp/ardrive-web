import 'package:flutter/material.dart';

class HorizontalDottedLine extends StatelessWidget {
  final double width;
  final Color color;

  const HorizontalDottedLine({
    super.key,
    required this.width,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: CustomPaint(
        painter: _HorizontalDottedLinePainter(color),
      ),
    );
  }
}

class _HorizontalDottedLinePainter extends CustomPainter {
  final Color color;

  _HorizontalDottedLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const double dashWidth = 5.0;
    const double dashSpace = 3.0;

    double startX = 0.0;
    while (startX < size.width) {
      canvas.drawLine(
          Offset(startX, 0.0), Offset(startX + dashWidth, 0.0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_HorizontalDottedLinePainter oldDelegate) {
    return color != oldDelegate.color;
  }
}
