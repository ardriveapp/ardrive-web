import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

part 'colors.dart';
part 'constants.dart';

final ThemeData theme = ThemeData.light();
final base = theme.copyWith(
  colorScheme: theme.colorScheme.copyWith(primary: kPrimarySwatch.shade900),
);

ThemeData appTheme() {
  final textTheme = _buildTextTheme(base.textTheme);

  return base.copyWith(
    primaryColor: kPrimarySwatch,
    primaryColorLight: kPrimarySwatch,
    accentColor: kSecondarySwatch.shade900,
    errorColor: errorColor,
    textTheme: textTheme,
    textSelectionTheme: _buildTextSelectionTheme(base.textSelectionTheme),
    iconTheme: _buildIconTheme(base.iconTheme),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: _buildAppBarTheme(base.appBarTheme),
    textButtonTheme: _buildTextButtonTheme(base.textButtonTheme),
    elevatedButtonTheme: _buildElevatedButtonTheme(base.elevatedButtonTheme),
    floatingActionButtonTheme:
        _buildFloatingActionButtonTheme(base.floatingActionButtonTheme),
    cardTheme: _buildCardTheme(base.cardTheme),
    inputDecorationTheme: _buildInputDecorationTheme(base.inputDecorationTheme),
    tabBarTheme: _buildTabBarTheme(base.tabBarTheme),
    dataTableTheme: _buildDataTableTheme(base.dataTableTheme),
    checkboxTheme: _buildCheckboxTheme(base.checkboxTheme),
    snackBarTheme: _buildSnackBarTheme(base.snackBarTheme),
    tooltipTheme: _buildToolTipTheme(base.tooltipTheme, textTheme),
  );
}

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
          fontSize: 24,
          fontWeight: FontWeight.w400,
          letterSpacing: 2,
          color: kPrimarySwatch),
      headline6: GoogleFonts.openSans(
          fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 2),
      subtitle1: GoogleFonts.openSans(
          fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.15),
      subtitle2: GoogleFonts.openSans(
          fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0.15),
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
      bodyColor: kOnSurfaceBodyTextColor,
      displayColor: kPrimarySwatch,
    )
    .merge(
      TextTheme(
        headline5:
            TextStyle(color: kPrimarySwatch, fontWeight: FontWeight.bold),
      ),
    );

IconThemeData _buildIconTheme(IconThemeData base) =>
    base.copyWith(color: kOnSurfaceBodyTextColor);

TextSelectionThemeData _buildTextSelectionTheme(TextSelectionThemeData base) =>
    base.copyWith(
      cursorColor: kPrimarySwatch,
      selectionColor: kSecondarySwatch.shade400,
      selectionHandleColor: kSecondarySwatch.shade600,
    );

AppBarTheme _buildAppBarTheme(AppBarTheme appBarBase) => appBarBase.copyWith(
      brightness: Brightness.light,
      color: Colors.white,
      centerTitle: false,
      iconTheme: _buildIconTheme(base.iconTheme),
    );

TextButtonThemeData _buildTextButtonTheme(TextButtonThemeData base) =>
    TextButtonThemeData(
      style: TextButton.styleFrom(
        primary: kOnSurfaceBodyTextColor,
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
      labelColor: kOnSurfaceBodyTextColor,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(width: 2, color: kPrimarySwatch),
      ),
    );

DataTableThemeData _buildDataTableTheme(DataTableThemeData base) =>
    base.copyWith(dataRowColor: MaterialStateColor.resolveWith(
      (states) {
        if (states.contains(MaterialState.hovered)) {
          return onSurfaceHoveredColor;
        } else if (states.contains(MaterialState.selected)) {
          return onSurfaceSelectedColor;
        }
        return Colors.transparent;
      },
    ));

SnackBarThemeData _buildSnackBarTheme(SnackBarThemeData base) => base.copyWith(
      behavior: SnackBarBehavior.floating,
      actionTextColor: kOnDarkSurfaceHighEmphasis,
    );

TooltipThemeData _buildToolTipTheme(
        TooltipThemeData base, TextTheme textTheme) =>
    base.copyWith(
      textStyle: textTheme.bodyText2!.copyWith(
        color: Colors.white,
        fontSize: 12,
      ),
    );

CheckboxThemeData _buildCheckboxTheme(CheckboxThemeData base) =>
    base.copyWith(fillColor: MaterialStateColor.resolveWith(
      (states) {
        if (states.contains(MaterialState.error)) {
          return errorColor;
        }

        return kPrimarySwatch;
      },
    ));
