import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class ArDriveTooltip extends StatelessWidget {
  const ArDriveTooltip({
    super.key,
    required this.child,
    required this.message,
  });

  final Widget child;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return Tooltip(
      message: message,
      decoration: BoxDecoration(
        color: colorTokens.buttonDisabled,
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: typography.paragraphNormal(
          fontWeight: ArFontWeight.semiBold, color: colorTokens.textMid),
      child: child,
    );
  }
}
