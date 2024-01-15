import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

enum ArrowSide { left, right, bottomLeft }

class FeedbackMessage extends StatelessWidget {
  const FeedbackMessage({
    Key? key,
    required this.text,
    this.textStyle,
    this.backgroundColor,
    this.borderColor,
    this.width,
    this.height = 50,
    this.arrowSide = ArrowSide.left,
  }) : super(key: key);

  final String text;
  final TextStyle? textStyle;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? width;
  final double height;
  final ArrowSide arrowSide;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TextBoxWithTrianglePainter(
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        arrowSide: arrowSide,
      ),
      child: Container(
        width: width,
        height: height,
        padding: _getPadding(),
        alignment: Alignment.center,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: textStyle ??
              ArDriveTypography.body.buttonNormalBold(
                color: ArDriveColors.dark().themeErrorDefault,
              ),
        ),
      ),
    );
  }

  EdgeInsets _getPadding() {
    if (arrowSide == ArrowSide.bottomLeft) {
      return const EdgeInsets.fromLTRB(8, 0, 8, 10);
    }
    return const EdgeInsets.fromLTRB(24, 8, 16, 8);
  }
}

class _TextBoxWithTrianglePainter extends CustomPainter {
  final Color? backgroundColor;
  final Color? borderColor;
  final ArrowSide arrowSide;

  _TextBoxWithTrianglePainter({
    this.backgroundColor,
    this.borderColor,
    required this.arrowSide,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(4);
    final rrect = RRect.fromRectAndRadius(
      arrowSide == ArrowSide.bottomLeft
          ? Rect.fromPoints(
              const Offset(0, 0),
              Offset(size.width, size.height - 10),
            )
          : arrowSide == ArrowSide.left
              ? Rect.fromPoints(
                  const Offset(0, 0),
                  Offset(size.width - size.height / 4, size.height),
                )
              : Rect.fromPoints(
                  Offset(size.height / 4, 0),
                  Offset(size.width, size.height),
                ),
      radius,
    );

    final borderPath = Path();

    final borderPaint = Paint()
      ..color = borderColor ?? const Color(0xff2E1C1F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(borderPath, borderPaint);

    // Fill path
    final fillPath = Path()
      ..addRRect(rrect)
      ..moveTo(
        arrowSide == ArrowSide.bottomLeft
            ? 20
            : arrowSide == ArrowSide.left
                ? size.width - size.height / 4
                : size.height / 4,
        arrowSide == ArrowSide.bottomLeft ? size.height - 10 : size.height / 4,
      )
      ..lineTo(
        arrowSide == ArrowSide.bottomLeft
            ? 30
            : arrowSide == ArrowSide.left
                ? size.width
                : 0,
        arrowSide == ArrowSide.bottomLeft ? size.height : size.height / 2,
      )
      ..lineTo(
        arrowSide == ArrowSide.bottomLeft
            ? 40
            : arrowSide == ArrowSide.left
                ? size.width - size.height / 4
                : size.height / 4,
        arrowSide == ArrowSide.bottomLeft
            ? size.height - 10
            : 3 * size.height / 4,
      );

    final fillPaint = Paint()
      ..color = backgroundColor ?? const Color(0xff2E1C1F)
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}
