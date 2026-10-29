import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_portal/flutter_portal.dart';

// ignore: library_private_types_in_public_api
GlobalKey<_ArDriveAppState> arDriveAppKey = GlobalKey();

class ArDriveUIThemeSwitcher {
  static void changeTheme(ArDriveThemes theme) {
    arDriveAppKey.currentState?.changeTheme(theme);
  }
}

enum ArDriveThemes { light, dark }

class ArDriveApp extends StatefulWidget {
  const ArDriveApp({
    super.key,
    required this.builder,
    this.themeData,
    this.onThemeChanged,
  });

  final Widget Function(BuildContext context) builder;
  final ArDriveThemeData? themeData;
  final Function(ArDriveThemes)? onThemeChanged;

  @override
  State<ArDriveApp> createState() => _ArDriveAppState();
}

class _ArDriveAppState extends State<ArDriveApp> {
  bool isDefault = true;

  late ArDriveThemes _theme;

  void changeTheme(ArDriveThemes theme) {
    setState(() {
      _theme = theme;
    });
  }

  @override
  void initState() {
    super.initState();

    // ignore: deprecated_member_use
    var window = WidgetsBinding.instance.window;
    WidgetsBinding.instance.handlePlatformBrightnessChanged();

    window.onPlatformBrightnessChanged = () {
      // This callback is called every time the brightness changes.
      var brightness = window.platformBrightness;

      setState(() {
        _theme = brightness == Brightness.dark
            ? ArDriveThemes.dark
            : ArDriveThemes.light;
      });

      widget.onThemeChanged?.call(_theme);
    };

    switch (widget.themeData?.name) {
      case 'ArDriveThemes.dark':
        _theme = ArDriveThemes.dark;
        break;
      case 'ArDriveThemes.light':
        _theme = ArDriveThemes.light;
        break;
      default:
        _theme = ArDriveThemes.dark;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ArDriveTheme(
      themeData: _getTheme(),
      child: Portal(
        child: Builder(builder: (context) {
          return widget.builder(context);
        }),
      ),
    );
  }

  ArDriveThemeData _getTheme() {
    switch (_theme) {
      case ArDriveThemes.dark:
        return widget.themeData ??
            ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode());
      case ArDriveThemes.light:
        return lightTheme();
      default:
        return ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode());
    }
  }
}

class ArDriveThemeData {
  ArDriveThemeData({
    Color? backgroundColor,
    Color? primaryColor,
    ArDriveToggleTheme? toggleTheme,
    ArDriveTableTheme? tableTheme,
    ThemeData? materialThemeData,
    String? name,
    ArDriveShadows? shadows,
    ArDriveDropdownTheme? dropdownTheme,
    ArDriveTextFieldTheme? textFieldTheme,

    // NEW THEME DATA
    required this.colorTokens,
  }) {
    this.shadows = shadows ?? ArDriveShadows(colorTokens);

    this.toggleTheme = toggleTheme ??
        ArDriveToggleTheme(
          backgroundOffDisabled: colorTokens.buttonDisabled,
          backgroundOffColor: colorTokens.containerL0,
          backgroundOnColor: const Color(0xff139310),
          indicatorColorDisabled: colorTokens.textLow,
          indicatorColorOff: colorTokens.iconMid,
        );
    this.tableTheme = tableTheme ??
        ArDriveTableTheme(
          backgroundColor: const Color(0xff121212),
          cellColor: const Color(0xff191919),
          hoverItemColor: const Color(0xff222222),
          selectedItemColor: const Color(0xff2C2C2C),
        );
    this.dropdownTheme = dropdownTheme ??
        ArDriveDropdownTheme(
          backgroundColor: colorTokens.containerRaised,
          hoverColor: const Color(0xff2C2C2C),
        );
    this.textFieldTheme = textFieldTheme ??
        ArDriveTextFieldTheme(
          errorColor: colorTokens.statusErrorFg,
          successColor: colorTokens.statusSuccessFg,
          successBorderColor: colorTokens.statusSuccessStroke,
          errorBorderColor: colorTokens.statusErrorStroke,
          inputDisabledBorderColor: colorTokens.strokeLow,
          defaultBorderColor: colorTokens.strokeMid,
          labelColor: colorTokens.textHigh,
          inputBackgroundColor: colorTokens.inputDefault,
          inputTextColor: colorTokens.textHigh,
          // The input size the old text styles had: 19.2px Wavehaus, 500.
          inputTextStyle: TextStyle(
            color: colorTokens.textHigh,
            fontFamily: 'Wavehaus',
            package: 'ardrive_ui',
            fontSize: 19.2,
            fontWeight: FontWeight.w500,
            height: 1.5,
          ),
          inputPlaceholderColor: colorTokens.textLow,
          disabledTextColor: colorTokens.textLow,
          requiredLabelColor: colorTokens.textHigh,
        );

    this.backgroundColor = backgroundColor ?? const Color(0xff010905);
    this.primaryColor = primaryColor ?? colorTokens.buttonPrimaryDefault;
    this.materialThemeData =
        materialThemeData ?? darkMaterialTheme(colorTokens);
    this.name = name ?? _darkTheme;
  }

  late Color backgroundColor;
  late Color primaryColor;
  late ArDriveToggleTheme toggleTheme;
  late ArDriveTableTheme tableTheme;
  late ArDriveDropdownTheme dropdownTheme;
  late ArDriveTextFieldTheme textFieldTheme;
  late ThemeData materialThemeData;
  late String name;
  late ArDriveShadows shadows;

  ArDriveColorTokens colorTokens;

  // copy with
  ArDriveThemeData copyWith({
    Color? backgroundColor,
    Color? primaryColor,
    ArDriveToggleTheme? toggleTheme,
    ArDriveTableTheme? tableTheme,
    ThemeData? materialThemeData,
    String? name,
    ArDriveShadows? shadows,
    ArDriveDropdownTheme? dropdownTheme,
    ArDriveTextFieldTheme? textFieldTheme,
    ArDriveColorTokens? colorTokens,
  }) {
    return ArDriveThemeData(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      primaryColor: primaryColor ?? this.primaryColor,
      toggleTheme: toggleTheme ?? this.toggleTheme,
      tableTheme: tableTheme ?? this.tableTheme,
      materialThemeData: materialThemeData ?? this.materialThemeData,
      name: name ?? this.name,
      shadows: shadows ?? this.shadows,
      dropdownTheme: dropdownTheme ?? this.dropdownTheme,
      textFieldTheme: textFieldTheme ?? this.textFieldTheme,
      colorTokens: colorTokens ?? this.colorTokens,
    );
  }
}

ThemeData lightMaterialTheme(ArDriveColorTokens colorTokens) {
  final ThemeData theme = ThemeData.light();

  return ThemeData(
    fontFamily: _fontFamily,
    primaryColor: colorTokens.buttonPrimaryDefault,
    primaryColorLight: colorTokens.buttonPrimaryDefault,
    colorScheme: theme.colorScheme.copyWith(
      background: colorTokens.containerRaised,
      primary: colorTokens.buttonPrimaryDefault,
      secondary: colorTokens.buttonPrimaryDefault,
      surface: colorTokens.containerRaised,
      onSurface: colorTokens.containerRaised,
    ),
    useMaterial3: false,
    textTheme: _bookByDefault(theme.textTheme.apply(
      fontFamily: _fontFamily,
      bodyColor: colorTokens.textHigh,
    )),
    primaryTextTheme: _bookByDefault(theme.primaryTextTheme.apply(
      fontFamily: _fontFamily,
    )),
  );
}

ArDriveThemeData lightTheme() {
  final colorTokens = ArDriveColorTokens.lightMode();

  return ArDriveThemeData(
      backgroundColor: colorTokens.containerRaised,
      // Warm light greys, like the surface tokens: the 2021 styleguide's
      // Gallery (#F1EFF0), and a page-level grey at the same tint.
      tableTheme: ArDriveTableTheme(
        backgroundColor: const Color(0xffFBF9FA),
        cellColor: const Color(0xffF1EFF0),
        hoverItemColor: const Color(0xffE8E5E7),
        // One step darker than a row, as dark's is one step lighter, so a
        // clicked row shows it is selected.
        selectedItemColor: colorTokens.containerL3,
      ),
      dropdownTheme: ArDriveDropdownTheme(
        backgroundColor: const Color(0xffFBF9FA),
        hoverColor: const Color(0xffF1EFF0),
      ),
      materialThemeData: lightMaterialTheme(colorTokens),
      name: _lightTheme,
      colorTokens: colorTokens);
}

// ignore: must_be_immutable
class ArDriveTheme extends InheritedWidget {
  ArDriveTheme({
    ArDriveThemeData? themeData,
    required super.child,
    super.key,
  }) {
    this.themeData = themeData ??
        ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode());
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

  bool isDark() {
    return themeData.name == _darkTheme;
  }

  bool isLight() {
    return themeData.name == _lightTheme;
  }
}

class ArDriveToggleTheme {
  ArDriveToggleTheme({
    this.indicatorColorOn = Colors.white,
    required this.indicatorColorOff,
    required this.indicatorColorDisabled,
    required this.backgroundOnColor,
    required this.backgroundOffColor,
    required this.backgroundOffDisabled,
  });

  final Color indicatorColorOn;
  final Color indicatorColorOff;
  final Color indicatorColorDisabled;
  final Color backgroundOnColor;
  final Color backgroundOffColor;
  final Color backgroundOffDisabled;
}

class ArDriveTableTheme {
  ArDriveTableTheme({
    required this.backgroundColor,
    required this.cellColor,
    required this.hoverItemColor,
    required this.selectedItemColor,
  });

  final Color backgroundColor;
  final Color cellColor;

  /// A row under the pointer: between a row and a selected row, so hover
  /// never reads as a selection.
  final Color hoverItemColor;
  final Color selectedItemColor;
}

class ArDriveDropdownTheme {
  ArDriveDropdownTheme({
    required this.backgroundColor,
    required this.hoverColor,
  });

  final Color backgroundColor;
  final Color hoverColor;
}

ThemeData darkMaterialTheme(ArDriveColorTokens colorTokens) {
  final ThemeData theme = ThemeData.dark();

  return ThemeData(
    fontFamily: _fontFamily,
    primaryColor: colorTokens.buttonPrimaryDefault,
    primaryColorLight: colorTokens.buttonPrimaryDefault,
    colorScheme: theme.colorScheme.copyWith(
      background: colorTokens.containerRaised,
      primary: colorTokens.buttonPrimaryDefault,
      secondary: colorTokens.buttonPrimaryDefault,
      surface: colorTokens.containerRaised,
      onSurface: colorTokens.containerRaised,
    ),
    useMaterial3: false,
    textTheme: _bookByDefault(theme.textTheme.apply(
      fontFamily: _fontFamily,
      bodyColor: colorTokens.textHigh,
    )),
    primaryTextTheme: _bookByDefault(theme.primaryTextTheme.apply(
      fontFamily: _fontFamily,
    )),
  );
}

const _fontFamily = 'packages/ardrive_ui/Wavehaus';

/// [textTheme] with nothing lighter than Book. Material's defaults are 400
/// (300 for its display styles), and Wavehaus declares Light as 400, so text
/// that names no weight (a plain `Text`, a snackbar, a tooltip) was drawn in
/// Light, which is for large figures only (README, "Tokens").
TextTheme _bookByDefault(TextTheme textTheme) {
  TextStyle? book(TextStyle? style) {
    if (style == null) return null;
    final weight = style.fontWeight ?? FontWeight.w400;
    return weight.index < FontWeight.w500.index
        ? style.copyWith(fontWeight: FontWeight.w500)
        : style;
  }

  return textTheme.copyWith(
    displayLarge: book(textTheme.displayLarge),
    displayMedium: book(textTheme.displayMedium),
    displaySmall: book(textTheme.displaySmall),
    headlineLarge: book(textTheme.headlineLarge),
    headlineMedium: book(textTheme.headlineMedium),
    headlineSmall: book(textTheme.headlineSmall),
    titleLarge: book(textTheme.titleLarge),
    titleMedium: book(textTheme.titleMedium),
    titleSmall: book(textTheme.titleSmall),
    bodyLarge: book(textTheme.bodyLarge),
    bodyMedium: book(textTheme.bodyMedium),
    bodySmall: book(textTheme.bodySmall),
    labelLarge: book(textTheme.labelLarge),
    labelMedium: book(textTheme.labelMedium),
    labelSmall: book(textTheme.labelSmall),
  );
}

const _lightTheme = 'light';
const _darkTheme = 'dark';
