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

const kHoverColor = Color.fromRGBO(249, 170, 51, 0.04);
const kFocusColor = Color.fromRGBO(249, 170, 51, 0.12);
const kSelectedColor = Color.fromRGBO(249, 170, 51, 0.08);

final kOnPrimaryHighEmphasis = Colors.white;
const kOnPrimaryMediumEmphasis = Color(0xFFDCE1E4);
const kOnPrimaryLowEmphasis = Color(0xFF17262A);
const kOnPrimaryDisabled = Color(0xFF767676);

const kDarkColor = Color(0xFF333333);
const kOnDarkHighEmphasis = Colors.white;
final kOnDarkMediumEmphasis = kOnDarkHighEmphasis.withOpacity(0.6);

const kOnBackground = Colors.black87;
