import 'package:ardrive_ui_library/src/styles/theme/themes.dart';
import 'package:flutter/material.dart';

enum BoxShadowCard { shadow20, shadow40, shadow60, shadow80, shadow100 }

class ArDriveCard extends StatelessWidget {
  const ArDriveCard({
    super.key,
    this.backgroundColor,
    this.borderRadius,
    this.elevation = 4.0,
    required this.content,
    this.contentPadding = const EdgeInsets.all(8),
    this.height,
    this.width,
    this.boxShadow,
  });

  final Color? backgroundColor;
  final double? borderRadius;
  final double elevation;
  final EdgeInsets contentPadding;
  final Widget content;
  final double? height;
  final double? width;
  final BoxShadowCard? boxShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: backgroundColor ??
            ArDriveTheme.of(context).themeData.colors.themeBgSurface,
        borderRadius: BorderRadius.circular(borderRadius ?? 8),
        boxShadow: [_getBoxShadow(boxShadow, context)],
      ),
      child: Padding(
        padding: contentPadding,
        child: content,
      ),
    );
  }

  BoxShadow _getBoxShadow(BoxShadowCard? boxShadowCard, BuildContext context) {
    switch (boxShadowCard) {
      case BoxShadowCard.shadow20:
        return ArDriveTheme.of(context).themeData.shadows.boxShadow20();

      case BoxShadowCard.shadow40:
        return ArDriveTheme.of(context).themeData.shadows.boxShadow40();

      case BoxShadowCard.shadow60:
        return ArDriveTheme.of(context).themeData.shadows.boxShadow60();

      case BoxShadowCard.shadow80:
        return ArDriveTheme.of(context).themeData.shadows.boxShadow80();

      case BoxShadowCard.shadow100:
        return ArDriveTheme.of(context).themeData.shadows.boxShadow100();

      default:
        return ArDriveTheme.of(context).themeData.shadows.boxShadow20();
    }
  }
}
