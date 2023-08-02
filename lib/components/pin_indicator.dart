import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class PinIndicator extends StatelessWidget {
  final double? size;

  const PinIndicator({
    Key? key,
    this.size,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ArDriveTheme.of(context).themeData.colors.themeBgSubtle,
      ),
      child: Center(
        child: ArDriveIcons.pinNoCircle(
          size: size,
          color: ArDriveTheme.of(context).themeData.colors.themeFgMuted,
        ),
      ),
    );
  }
}
