import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

export 'colors.dart';
export 'constants.dart';

final base = ThemeData.light();

ThemeData appTheme() {
  final textTheme = GoogleFonts.openSansTextTheme().copyWith(
    button: GoogleFonts.montserrat(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      fontStyle: FontStyle.normal,
      letterSpacing: 1,
    ),
  );

  return base.copyWith(
    primaryColor: kPrimarySwatch,
    primaryColorLight: kPrimarySwatch,
    accentColor: kSecondarySwatch.shade900,
    textTheme: textTheme,
    textSelectionTheme: _buildTextSelectionTheme(base.textSelectionTheme),
    iconTheme: _buildIconTheme(base.iconTheme),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: _buildAppBarTheme(base.appBarTheme),
    textButtonTheme: _buildTextButtonTheme(base.textButtonTheme),
    elevatedButtonTheme: _buildElevatedButtonTheme(base.elevatedButtonTheme),
    floatingActionButtonTheme:
        _buildFloatingActionButtonTheme(base.floatingActionButtonTheme),
    inputDecorationTheme: _buildInputDecorationTheme(base.inputDecorationTheme),
    tabBarTheme: _buildTabBarTheme(base.tabBarTheme),
  );
}

IconThemeData _buildIconTheme(IconThemeData base) =>
    base.copyWith(color: Colors.black87);

TextSelectionThemeData _buildTextSelectionTheme(TextSelectionThemeData base) =>
    base.copyWith(
      selectionColor: kSecondarySwatch.shade400,
      selectionHandleColor: kSecondarySwatch.shade600,
    );

AppBarTheme _buildAppBarTheme(AppBarTheme base) =>
    base.copyWith(color: Colors.white);

TextButtonThemeData _buildTextButtonTheme(TextButtonThemeData base) =>
    TextButtonThemeData(
      style: TextButton.styleFrom(
        primary: Colors.black87,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
      ),
    );

ElevatedButtonThemeData _buildElevatedButtonTheme(
        ElevatedButtonThemeData base) =>
    ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        primary: kPrimarySwatch,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
      ),
    );

FloatingActionButtonThemeData _buildFloatingActionButtonTheme(
        FloatingActionButtonThemeData base) =>
    base.copyWith(backgroundColor: kPrimarySwatch);

InputDecorationTheme _buildInputDecorationTheme(InputDecorationTheme base) =>
    base.copyWith(filled: true);

TabBarTheme _buildTabBarTheme(TabBarTheme base) => base.copyWith(
      labelColor: Colors.black87,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(width: 2, color: kPrimarySwatch),
      ),
    );
