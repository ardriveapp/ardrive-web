import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class PinIndicator extends StatelessWidget {
  final double size;

  const PinIndicator({
    Key? key,
    required this.size,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ArDriveTheme.of(context)
            .themeData
            .colors
            .themeFgMuted
            .withAlpha(25),
        border: Border.all(
          color: ArDriveTheme.of(context)
              .themeData
              .colors
              .themeGbMuted
              .withAlpha(25),
          width: 2,
        ),
      ),
      child: Center(
        child: ArDriveIcons.pinNoCircle(
          size: size * .8,
          color: ArDriveTheme.of(context).themeData.colors.themeFgMuted,
        ),
      ),
    );
  }
}
