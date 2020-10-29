import 'package:flutter/material.dart';

const kPrimaryValue = 0xFF700327;
const kPrimarySwatch = MaterialColor(
  kPrimaryValue,
  <int, Color>{
    50: Color(0xFFfae2e3),
    100: Color(0xFFf3b5ba),
    200: Color(0xFFe8878e),
    300: Color(0xFFdb5a64),
    400: Color(0xFFd03c47),
    500: Color(0xFFc5252d),
    600: Color(0xFFb61f2d),
    700: Color(0xFFa3192c),
    800: Color(0xFF91102b),
    900: Color(kPrimaryValue),
  },
);

const kSecondaryValue = 0xFF344955;
const kSecondarySwatch = MaterialColor(
  kPrimaryValue,
  <int, Color>{
    50: Color(0xFFE8F0F6),
    100: Color(0xFFCBD9E1),
    200: Color(0xFFADC0CB),
    300: Color(0xFF8DA6B5),
    400: Color(0xFF7592A3),
    500: Color(0xFF5D7F92),
    600: Color(0xFF517081),
    700: Color(0xFF425C6A),
    800: Color(kPrimaryValue),
    900: Color(0xFF23343E),
  },
);

const kOnSurfaceBodyTextColor = Colors.black87;
final onSurfaceHoveredColor = kPrimarySwatch.withOpacity(0.04);
final onSurfaceFocusColor = kPrimarySwatch.withOpacity(0.12);
final onSurfaceSelectedColor = kPrimarySwatch.withOpacity(0.12);

const kDarkSurfaceColor = Color(0xFF333333);
const kOnDarkSurfaceHighEmphasis = Colors.white;
const kOnDarkSurfaceMediumEmphasis = Colors.white60;
final onDarkSurfaceSelectedColor = kPrimarySwatch.shade300.withOpacity(0.12);
