import 'package:ardrive/components/theme_switcher.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class IconThemeSwitcher extends StatelessWidget {
  const IconThemeSwitcher({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return ThemeSwitcher(
      customLightModeContent: ArDriveIcons.moon(
        color: colorTokens.iconLow,
      ),
      customDarkModeContent: Icon(
        Icons.sunny,
        color: color ?? colorTokens.iconLow,
      ),
    );
  }
}
