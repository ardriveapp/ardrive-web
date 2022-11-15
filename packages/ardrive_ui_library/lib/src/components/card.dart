import 'package:ardrive_ui_library/src/styles/theme/themes.dart';
import 'package:flutter/material.dart';

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
  });

  final Color? backgroundColor;
  final double? borderRadius;
  final double elevation;
  final EdgeInsets contentPadding;
  final Widget content;
  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: Card(
        color: backgroundColor ??
            ArDriveTheme.of(context).themeData.colors.themeBgSurface,
        elevation: elevation,
        shadowColor: ArDriveTheme.of(context).themeData.colors.themeBgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            borderRadius ?? 10,
          ),
        ),
        child: Padding(
          padding: contentPadding,
          child: content,
        ),
      ),
    );
  }
}
