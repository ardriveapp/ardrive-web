import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class ArDriveScrollBar extends StatelessWidget {
  const ArDriveScrollBar({
    super.key,
    required this.child,
    this.controller,
    this.isVisible = true,
    this.alwaysVisible = false,
  });

  final Widget child;
  final ScrollController? controller;
  final bool isVisible;
  final bool alwaysVisible;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final thumbColor = isVisible
        ? colors.themeBorderDefault.withOpacity(0.9)
        : Colors.transparent;
    final trackColor = isVisible
        ? colors.themeBorderDefault.withOpacity(0.5)
        : Colors.transparent;

    return Theme(
      data: ArDriveTheme.of(context).themeData.materialThemeData.copyWith(
            scrollbarTheme: ScrollbarThemeData(
              thumbColor: MaterialStateProperty.all<Color>(thumbColor),
              trackColor: MaterialStateProperty.all<Color>(trackColor),
              thickness: MaterialStateProperty.all<double>(4.0),
            ),
          ),
      child: isVisible
          ? Scrollbar(
              interactive: true,
              thumbVisibility: alwaysVisible,
              controller: controller,
              thickness: 4.0,
              child: child,
            )
          : child,
    );
  }
}
