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
    ArDriveColors? colors,
    ArDriveShadows? shadows,
    ArDriveDropdownTheme? dropdownTheme,
    ArDriveTextFieldTheme? textFieldTheme,

    // NEW THEME DATA
    required this.colorTokens,
  }) {
    this.colors = colors ?? ArDriveColors();
    this.shadows = shadows ?? ArDriveShadows(this.colors);

    this.toggleTheme = toggleTheme ??
        ArDriveToggleTheme(
          backgroundOffDisabled: this.colors.themeFgDisabled,
          backgroundOffColor: colorTokens.containerL0,
          backgroundOnColor: const Color(0xff139310),
          indicatorColorDisabled: this.colors.themeFgOnDisabled,
          indicatorColorOff: colorTokens.iconMid,
        );
    this.tableTheme = tableTheme ??
        ArDriveTableTheme(
          backgroundColor: const Color(0xff121212),
          cellColor: const Color(0xff191919),
          selectedItemColor: const Color(0xff2C2C2C),
        );
    this.dropdownTheme = dropdownTheme ??
        ArDriveDropdownTheme(
          backgroundColor: this.colors.themeBgSurface,
          hoverColor: const Color(0xff2C2C2C),
        );
    this.textFieldTheme = textFieldTheme ??
        ArDriveTextFieldTheme(
          errorColor: this.colors.themeErrorDefault,
          successColor: this.colors.themeSuccessDefault,
          successBorderColor: this.colors.themeSuccessEmphasis,
          errorBorderColor: this.colors.themeErrorOnEmphasis,
          inputDisabledBorderColor: this.colors.themeInputBorderDisabled,
          defaultBorderColor: this.colors.themeBorderDefault,
          labelColor: this.colors.themeFgDefault,
          inputBackgroundColor: this.colors.themeInputBackground,
          inputTextColor: this.colors.themeInputText,
          inputTextStyle: ArDriveTypography.body.inputLargeRegular(
            color: this.colors.themeInputText,
          ),
          inputPlaceholderColor: this.colors.themeInputPlaceholder,
          disabledTextColor: this.colors.themeFgDisabled,
          requiredLabelColor: this.colors.themeFgDefault,
        );

    this.backgroundColor = backgroundColor ?? const Color(0xff010905);
    this.primaryColor = primaryColor ?? this.colors.themeAccentBrand;
    this.materialThemeData = materialThemeData ?? darkMaterialTheme();
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
  late ArDriveColors colors;
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
    ArDriveColors? colors,
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
      colors: colors ?? this.colors,
      shadows: shadows ?? this.shadows,
      dropdownTheme: dropdownTheme ?? this.dropdownTheme,
      textFieldTheme: textFieldTheme ?? this.textFieldTheme,
      colorTokens: colorTokens ?? this.colorTokens,
    );
  }
}

ThemeData lightMaterialTheme() {
  final ThemeData theme = ThemeData.light();
  ArDriveColors colors = ArDriveColors.light();

  return ThemeData(
    fontFamily: _fontFamily,
    primaryColor: colors.themeAccentBrand,
    primaryColorLight: colors.themeAccentBrand,
    colorScheme: theme.colorScheme.copyWith(
      background: colors.themeBgSurface,
      primary: colors.themeAccentBrand,
      secondary: colors.themeAccentBrand,
      surface: colors.themeBgSurface,
      onSurface: colors.themeBgSurface,
    ),
    useMaterial3: false,
    textTheme: theme.textTheme.apply(
      fontFamily: _fontFamily,
      bodyColor: colors.themeFgDefault,
    ),
  );
}

ArDriveThemeData lightTheme() {
  ArDriveColors colors = ArDriveColors.light();

  return ArDriveThemeData(
      backgroundColor: colors.themeBgSurface,
      colors: colors,
      tableTheme: ArDriveTableTheme(
        backgroundColor: const Color(0xffFAFAFA),
        cellColor: const Color(0xffF1EFF0),
        selectedItemColor: const Color(0xffF1EFF0),
      ),
      dropdownTheme: ArDriveDropdownTheme(
        backgroundColor: const Color(0xffFAFAFA),
        hoverColor: const Color(0xffF1EFF0),
      ),
      materialThemeData: lightMaterialTheme(),
      name: _lightTheme,
      colorTokens: ArDriveColorTokens.lightMode());
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
    required this.selectedItemColor,
  });

  final Color backgroundColor;
  final Color cellColor;
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

ThemeData darkMaterialTheme() {
  final ThemeData theme = ThemeData.dark();
  ArDriveColors colors = ArDriveColors.dark();

  return ThemeData(
    fontFamily: _fontFamily,
    primaryColor: colors.themeAccentBrand,
    primaryColorLight: colors.themeAccentBrand,
    colorScheme: theme.colorScheme.copyWith(
      background: colors.themeBgSurface,
      primary: colors.themeAccentBrand,
      secondary: colors.themeAccentBrand,
      surface: colors.themeBgSurface,
      onSurface: colors.themeBgSurface,
    ),
    useMaterial3: false,
    textTheme: theme.textTheme.apply(
      fontFamily: _fontFamily,
      bodyColor: colors.themeFgDefault,
    ),
  );
}

const _fontFamily = 'packages/ardrive_ui/Wavehaus';

const _lightTheme = 'light';
const _darkTheme = 'dark';
