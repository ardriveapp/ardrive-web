import 'package:flutter/material.dart';

import 'monospace.dart';

const String _package = 'ardrive_ui';

const String fontFamily = 'Wavehaus';

enum ArFontWeight {
  book(FontWeight.w500),
  semiBold(FontWeight.w600),
  bold(FontWeight.w700);

  const ArFontWeight(this.weight);
  final FontWeight weight;
}

TextStyle _textStyle(
    {required double fontSize,
    double height = 1.3,
    Color? color,
    ArFontWeight? fontWeight}) {
  return TextStyle(
    color: color,
    fontFamily: fontFamily,
    package: _package,
    fontSize: fontSize,
    fontWeight: fontWeight?.weight ?? ArFontWeight.book.weight,
    height: height,
  );
}

abstract class ArdriveTypographyNew {
  TextStyle display({Color? color, ArFontWeight? fontWeight});

  TextStyle heading1({Color? color, ArFontWeight? fontWeight});
  TextStyle heading2({Color? color, ArFontWeight? fontWeight});
  TextStyle heading3({Color? color, ArFontWeight? fontWeight});
  TextStyle heading4({Color? color, ArFontWeight? fontWeight});
  TextStyle heading5({Color? color, ArFontWeight? fontWeight});
  TextStyle heading6({Color? color, ArFontWeight? fontWeight});

  TextStyle paragraphXXLarge({Color? color, ArFontWeight? fontWeight});
  TextStyle paragraphXLarge({Color? color, ArFontWeight? fontWeight});
  TextStyle paragraphLarge({Color? color, ArFontWeight? fontWeight});
  TextStyle paragraphNormal({Color? color, ArFontWeight? fontWeight});
  TextStyle paragraphSmall({Color? color, ArFontWeight? fontWeight});
  TextStyle caption({Color? color, ArFontWeight? fontWeight});

  /// Roboto Mono, for code, text-file previews and the note editor only.
  /// Starts loading the face the first time it is asked for; see
  /// [ArDriveMonospace]. [fontSize] defaults to a step under paragraphNormal,
  /// where monospace reads the same size.
  TextStyle code({Color? color, double? fontSize});
}

TextStyle _codeStyle({required double fontSize, Color? color}) {
  ArDriveMonospace.ensureLoaded();
  return TextStyle(
    color: color,
    fontFamily: ArDriveMonospace.family,
    fontFamilyFallback: ArDriveMonospace.fallback,
    fontSize: fontSize,
    // Regular is the one weight bundled; the fallback's book weight matches
    // the body text while the face loads.
    fontWeight: ArFontWeight.book.weight,
    height: 1.5,
  );
}

class ArDriveDesktopTypography implements ArdriveTypographyNew {
  @override
  TextStyle display({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(fontSize: 45, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle heading1({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(fontSize: 36, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle heading2({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(fontSize: 28, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle heading3({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(fontSize: 25, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle heading4({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 22, height: 1.4, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle heading5({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 20, height: 1.4, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle heading6({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 18, height: 1.4, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle paragraphXXLarge({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 20, height: 1.4, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle paragraphXLarge({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 18, height: 1.5, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle paragraphLarge({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 16, height: 1.5, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle paragraphNormal({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 14, height: 1.5, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle paragraphSmall({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 12, height: 1.5, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle caption({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 11, height: 1.5, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle code({Color? color, double? fontSize}) =>
      _codeStyle(fontSize: fontSize ?? 13, color: color);
}

class ArDriveMobileTypography implements ArdriveTypographyNew {
  @override
  TextStyle display({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(fontSize: 30, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle heading1({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(fontSize: 28, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle heading2({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(fontSize: 26, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle heading3({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(fontSize: 23, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle heading4({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 21, height: 1.4, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle heading5({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 19, height: 1.4, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle heading6({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 16, height: 1.5, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle paragraphXXLarge({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 19, height: 1.4, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle paragraphXLarge({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 16, height: 1.5, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle paragraphLarge({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 15, height: 1.5, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle paragraphNormal({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 13, height: 1.5, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle paragraphSmall({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 12, height: 1.5, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle caption({Color? color, ArFontWeight? fontWeight}) {
    return _textStyle(
        fontSize: 10, height: 1.5, color: color, fontWeight: fontWeight);
  }

  @override
  TextStyle code({Color? color, double? fontSize}) =>
      _codeStyle(fontSize: fontSize ?? 12, color: color);
}

// FIXME: Rename this to not be confusing wing ArdriveTypographyNew
class ArDriveTypographyNew {
  static ArdriveTypographyNew desktop = ArDriveDesktopTypography();
  static ArdriveTypographyNew mobile = ArDriveMobileTypography();

  static ArdriveTypographyNew of(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width < 834 ? mobile : desktop;
  }
}
