part of 'theme.dart';

class LightColors {
  static const kPrimaryValue = 0xFF700327;
  static const kPrimarySwatch = MaterialColor(
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

  static const kSecondaryValue = 0xFF344955;
  static const kSecondarySwatch = MaterialColor(
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

  static const kOnSurfaceBodyTextColor = Colors.black87;
  final onSurfaceHoveredColor = kPrimarySwatch.withOpacity(0.04);
  final onSurfaceFocusColor = kPrimarySwatch.withOpacity(0.12);
  final onSurfaceSelectedColor = kPrimarySwatch.withOpacity(0.12);

  static const kDarkSurfaceColor = Color(0xFF333333);
  static const kOnDarkSurfaceHighEmphasis = Colors.white;
  static const kOnDarkSurfaceMediumEmphasis = Colors.white60;
  static const kOnLightSurfaceMediumEmphasis = Color(0xFF121212);
  final onDarkSurfaceSelectedColor = kPrimarySwatch.shade300.withOpacity(0.12);

  final errorColor = kPrimarySwatch.shade300;
}

const kPrimaryValue = 0xFFFE0230;
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

const kDarkSurfaceColor = Color(0xFF0A0B09);
const kOnDarkSurfaceHighEmphasis = Colors.white;
const kOnDarkSurfaceMediumEmphasis = Colors.white60;
final onDarkSurfaceSelectedColor = kPrimarySwatch.shade300.withOpacity(0.12);

final errorColor = kPrimarySwatch.shade300;
