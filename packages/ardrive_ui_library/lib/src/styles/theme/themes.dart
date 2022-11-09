import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:ardrive_ui_library/src/styles/colors/global_colors.dart';
import 'package:flutter/material.dart';

class ArDriveApp extends StatefulWidget {
  const ArDriveApp({super.key, required this.builder});
  final Widget Function(BuildContext context) builder;

  @override
  State<ArDriveApp> createState() => _ArDriveAppState();
}

class _ArDriveAppState extends State<ArDriveApp> {
  @override
  Widget build(BuildContext context) {
    return ArDriveTheme(
      child: Builder(builder: (context) {
        return widget.builder(context);
      }),
    );
  }
}

class ArDriveThemeData {
  ArDriveThemeData({
    Color? backgroundColor,
    Color? primaryColor,
    ArDriveToggleTheme? toggleTheme,
    ThemeData? materialThemeData,
    String? name,
  }) {
    this.backgroundColor = backgroundColor ?? ArDriveColors.themeBgSubtle;
    this.primaryColor = primaryColor ?? ArDriveColors.themeAccentBrand;
    this.toggleTheme = toggleTheme ?? ArDriveToggleTheme();
    this.materialThemeData = materialThemeData ?? darkTheme();
    this.name = name ?? 'default';
  }

  late Color backgroundColor;
  late Color primaryColor;
  late ArDriveToggleTheme toggleTheme;
  late ThemeData materialThemeData;
  late String name;
}

ThemeData lightMaterialTheme() {
  final ThemeData theme = ThemeData.light();

  return ThemeData(
    fontFamily: 'Wavehaus',
    primaryColor: ArDriveColors.themeAccentBrand,
    primaryColorLight: ArDriveColors.themeAccentBrand,
    colorScheme: theme.colorScheme.copyWith(
      background: ArDriveColors.themeBgSurface,
      primary: ArDriveColors.themeAccentBrand,
      secondary: ArDriveColors.themeAccentBrand,
    ),
  );
}

ArDriveThemeData lightTheme() {
  final toggleThemeLight = ArDriveToggleTheme(
    backgroundOffColor: blue.shade50,
    backgroundOnColor: black,
    backgroundOffDisabled: ArDriveColors.themeFgOnDisabled,
    indicatorColorDisabled: ArDriveColors.themeFgDisabled,
    indicatorColorOff: blue,
    indicatorColorOn: blue.shade50,
  );

  return ArDriveThemeData(
    primaryColor: ArDriveColors.themeAccentBrand,
    materialThemeData: lightMaterialTheme(),
    backgroundColor: ArDriveColors.themeBgSurface,
    toggleTheme: toggleThemeLight,
    name: 'light',
  );
}

// ignore: must_be_immutable
class ArDriveTheme extends InheritedWidget {
  ArDriveTheme({
    ArDriveThemeData? themeData,
    required super.child,
    super.key,
  }) {
    this.themeData = themeData ?? ArDriveThemeData();
  }

  late ArDriveThemeData themeData;

  @override
  bool updateShouldNotify(ArDriveTheme oldWidget) =>
      themeData != oldWidget.themeData;
  static ArDriveTheme of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<ArDriveTheme>();

    if (theme != null) {
      return theme;
    }

    throw Exception('Not found a ArDriveTheme in the widget tree');
  }
}

class ArDriveToggleTheme {
  ArDriveToggleTheme({
    Color? indicatorColorOn,
    Color? indicatorColorOff,
    Color? indicatorColorDisabled,
    Color? backgroundOnColor,
    Color? backgroundOffColor,
    Color? backgroundOffDisabled,
  }) {
    this.indicatorColorOn = indicatorColorOn ?? black;
    this.indicatorColorOff = indicatorColorOff ?? blue.shade500;
    this.indicatorColorDisabled =
        indicatorColorDisabled ?? ArDriveColors.themeFgDisabled;
    this.backgroundOffColor = backgroundOffColor ?? black;
    this.backgroundOnColor = backgroundOnColor ?? ArDriveColors.themeFgDefault;
    this.backgroundOffDisabled = backgroundOffDisabled ?? grey.shade400;
  }

  late Color indicatorColorOn;
  late Color indicatorColorOff;
  late Color indicatorColorDisabled;

  late Color backgroundOnColor;
  late Color backgroundOffColor;
  late Color backgroundOffDisabled;
}

ThemeData darkTheme() {
  final ThemeData theme = ThemeData.dark();

  return ThemeData(
    primaryColor: ArDriveColors.themeAccentBrand,
    primaryColorLight: ArDriveColors.themeAccentBrand,
    fontFamily: 'Wavehaus',
    colorScheme: theme.colorScheme.copyWith(
      background: ArDriveColors.themeBgSurface,
      primary: ArDriveColors.themeAccentBrand,
      secondary: ArDriveColors.themeAccentBrand,
    ),
  );
}
