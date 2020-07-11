import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

ThemeData appTheme() {
  return ThemeData(
    colorScheme: ColorScheme.light().copyWith(
      primary: kPrimary700,
      secondary: kSecondary500,
    ),
    primaryColor: kPrimary700,
    accentColor: kSecondary500,
    hoverColor: kHoverColor,
    highlightColor: kSelectedColor,
    textTheme: _buildTextTheme(),
    appBarTheme: _buildAppBarTheme(),
    navigationRailTheme: _buildNavigationRailTheme(),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
    ),
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}

TextTheme _buildTextTheme() => TextTheme(
      headline1: GoogleFonts.workSans(
        fontWeight: FontWeight.w300,
        fontSize: 96.0,
      ),
      headline2: GoogleFonts.workSans(
        fontWeight: FontWeight.w600,
        fontSize: 60.0,
      ),
      headline3: GoogleFonts.workSans(
        fontWeight: FontWeight.w400,
        fontSize: 48.0,
      ),
      headline4: GoogleFonts.workSans(
        fontWeight: FontWeight.bold,
        fontSize: 34,
        letterSpacing: 0.4,
        height: 0.9,
        color: kOnSurfaceMediumEmphasis,
      ),
      headline5: GoogleFonts.workSans(
        fontWeight: FontWeight.w700,
        fontSize: 24.0,
      ),
      headline6: GoogleFonts.workSans(
        fontWeight: FontWeight.w500,
        fontSize: 20.0,
      ),
      subtitle1: GoogleFonts.workSans(
        fontWeight: FontWeight.w400,
        fontSize: 16.0,
      ),
      subtitle2: GoogleFonts.workSans(
        fontWeight: FontWeight.w500,
        fontSize: 14.0,
      ),
      bodyText1: GoogleFonts.workSans(
        fontWeight: FontWeight.w400,
        fontSize: 18.0,
      ),
      bodyText2: GoogleFonts.workSans(
        fontWeight: FontWeight.w400,
        fontSize: 14.0,
      ),
      button: GoogleFonts.workSans(
        fontWeight: FontWeight.w500,
        fontSize: 14.0,
      ),
      caption: GoogleFonts.workSans(
        fontWeight: FontWeight.w400,
        fontSize: 12.0,
        color: kOnSurfaceLowEmphasis,
      ),
      overline: GoogleFonts.workSans(
        fontWeight: FontWeight.w600,
        fontSize: 12.0,
      ),
    );

AppBarTheme _buildAppBarTheme() => AppBarTheme(
      color: kPrimary800,
    );

NavigationRailThemeData _buildNavigationRailTheme() => NavigationRailThemeData(
      backgroundColor: kPrimary700,
      selectedIconTheme: IconThemeData(color: kOnPrimaryHighEmphasis),
      selectedLabelTextStyle: TextStyle(color: kOnPrimaryHighEmphasis),
      unselectedIconTheme: IconThemeData(color: kOnPrimaryMediumEmphasis),
      unselectedLabelTextStyle: TextStyle(color: kOnPrimaryMediumEmphasis),
    );
