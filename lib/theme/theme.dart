import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

export 'colors.dart';
export 'constants.dart';

final base = ThemeData.light();

ThemeData appTheme() => base.copyWith(
      primaryColor: kPrimarySwatch,
      primaryColorLight: kPrimarySwatch,
      accentColor: kSecondarySwatch.shade900,
      textTheme: _buildTextTheme(base.textTheme),
      textSelectionTheme: _buildTextSelectionTheme(base.textSelectionTheme),
      iconTheme: _buildIconTheme(base.iconTheme),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: _buildAppBarTheme(base.appBarTheme),
      textButtonTheme: _buildTextButtonTheme(base.textButtonTheme),
      elevatedButtonTheme: _buildElevatedButtonTheme(base.elevatedButtonTheme),
      floatingActionButtonTheme:
          _buildFloatingActionButtonTheme(base.floatingActionButtonTheme),
      cardTheme: _buildCardTheme(base.cardTheme),
      inputDecorationTheme:
          _buildInputDecorationTheme(base.inputDecorationTheme),
      tabBarTheme: _buildTabBarTheme(base.tabBarTheme),
      dataTableTheme: _buildDataTableTheme(base.dataTableTheme),
    );

TextTheme _buildTextTheme(TextTheme base) => base
    .copyWith(
      headline1: GoogleFonts.montserrat(
          fontSize: 97, fontWeight: FontWeight.w300, letterSpacing: -1.5),
      headline2: GoogleFonts.montserrat(
          fontSize: 61, fontWeight: FontWeight.w300, letterSpacing: -0.5),
      headline3:
          GoogleFonts.montserrat(fontSize: 48, fontWeight: FontWeight.w400),
      headline4: GoogleFonts.montserrat(
          fontSize: 34, fontWeight: FontWeight.w400, letterSpacing: 0.25),
      headline5: GoogleFonts.montserrat(
          fontSize: 24, fontWeight: FontWeight.w400, letterSpacing: 2),
      headline6: GoogleFonts.openSans(
          fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 2),
      subtitle1: GoogleFonts.openSans(
          fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.15),
      subtitle2: GoogleFonts.montserrat(
          fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
      bodyText1: GoogleFonts.openSans(
          fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.5),
      bodyText2: GoogleFonts.openSans(
          fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0.25),
      button: GoogleFonts.montserrat(
          fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 1.25),
      caption: GoogleFonts.openSans(
          fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.4),
      overline: GoogleFonts.openSans(
          fontSize: 10, fontWeight: FontWeight.w400, letterSpacing: 1.5),
    )
    .apply(
      bodyColor: Colors.black87,
      displayColor: Colors.black87,
    );

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

CardTheme _buildCardTheme(CardTheme base) => base.copyWith(elevation: 0);

TabBarTheme _buildTabBarTheme(TabBarTheme base) => base.copyWith(
      labelColor: Colors.black87,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(width: 2, color: kPrimarySwatch),
      ),
    );

DataTableThemeData _buildDataTableTheme(DataTableThemeData base) =>
    base.copyWith(dataRowColor: MaterialStateColor.resolveWith(
      (states) {
        if (states.contains(MaterialState.selected)) {
          return kPrimarySwatch.withOpacity(0.12);
        }
        return Colors.transparent;
      },
    ));
