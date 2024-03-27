import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_ui/src/styles/colors/global_colors.dart';
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
    return Theme(
      data: ArDriveTheme.of(context).themeData.materialThemeData.copyWith(
            scrollbarTheme: ScrollbarThemeData(
              thumbColor: MaterialStateProperty.all<Color>(
                isVisible ? grey.shade400 : Colors.transparent,
              ), // set the color of the thumb
              trackColor: MaterialStateProperty.all<Color>(
                isVisible ? grey.shade400 : Colors.transparent,
              ), // set the color of the track
            ),
          ),
      child: isVisible
          ? Scrollbar(
              interactive: true,
              thumbVisibility: alwaysVisible,
              controller: controller,
              child: child,
            )
          : child,
    );
  }
}
