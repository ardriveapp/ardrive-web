import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class PinIndicator extends StatelessWidget {
  final double size;

  const PinIndicator({
    super.key,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorTokens.strokeLow,
        border: Border.all(color: colorTokens.strokeMid, width: 2),
      ),
      child: Center(
        child: ArDriveIcons.pinNoCircle(
          size: size * .8,
          color: colorTokens.textMid,
        ),
      ),
    );
  }
}
