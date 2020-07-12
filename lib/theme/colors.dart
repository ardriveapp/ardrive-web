import 'package:flutter/material.dart';

const kPrimaryValue = 0xFF344955;
const kPrimarySwatch = MaterialColor(
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

const kSecondaryValue = 0xFFF9AA33;
const kSecondarySwatch = MaterialColor(
  kSecondaryValue,
  <int, Color>{
    50: Color(0xFFFFFDE8),
    100: Color(0xFFFFF9C6),
    200: Color(0xFFFFF5A0),
    300: Color(0xFFFFF07B),
    400: Color(0xFFFDEB5D),
    500: Color(0xFFFBE642),
    600: Color(0xFFFFD942),
    700: Color(0xFFFCC13B),
    800: Color(kSecondaryValue),
    900: Color(0xFFF48226),
  },
);

const kSecondary500 = const Color(0xFFF9AA33);

const kHoverColor = const Color.fromRGBO(249, 170, 51, 0.04);
const kFocusColor = const Color.fromRGBO(249, 170, 51, 0.12);
const kSelectedColor = const Color.fromRGBO(249, 170, 51, 0.08);

const kOnSurfaceHighEmphasis = kSecondary500;
const kOnSurfaceMediumEmphasis = const Color(0xFF17262A);
const kOnSurfaceLowEmphasis = const Color(0xFF767676);
const kOnSurfaceDisabled = const Color(0xFF253840);

const kOnPrimaryHighEmphasis = kSecondary500;
const kOnPrimaryMediumEmphasis = const Color(0xFFDCE1E4);
const kOnPrimaryLowEmphasis = const Color(0xFF17262A);
const kOnPrimaryDisabled = const Color(0xFF767676);
