import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const String _package = 'ardrive_ui';

class ArDriveTypography {
  static Body body = const Body();
  static Headline headline = const Headline();
}

class Body {
  const Body();

  /// **fontSizeXXS** - 9px
  TextStyle tinyRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeXXS,
      fontWeight: FontWeight.w500,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeXXS** - 9px
  TextStyle tinyBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeXXS,
      fontWeight: FontWeight.w600,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeXS** - 11px
  TextStyle xSmallRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeXS,
      fontWeight: FontWeight.w500,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeXS** - 11px
  TextStyle xSmallBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeXS,
      fontWeight: FontWeight.w600,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeSM** - 13px
  TextStyle captionRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeSM,
      fontWeight: FontWeight.w500,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeSM** - 13px
  TextStyle captionBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeSM,
      fontWeight: FontWeight.w600,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeSM** - 13px
  TextStyle buttonNormalRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeSM,
      fontWeight: FontWeight.w500,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeSM** - 13px
  TextStyle buttonNormalBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeSM,
      fontWeight: FontWeight.w600,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeBase** - 16px
  TextStyle smallRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeBase,
      fontWeight: FontWeight.w500,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeBase** - 16px
  TextStyle smallBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeBase,
      fontWeight: FontWeight.w600,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeBase** - 16px
  TextStyle smallBold700({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeBase,
      fontWeight: FontWeight.w700,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeBase** - 16px
  TextStyle inputNormalRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeBase,
      fontWeight: FontWeight.w500,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeBase** - 16px
  TextStyle inputNormalBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeBase,
      fontWeight: FontWeight.w600,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeBase** - 16px
  TextStyle buttonLargeRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeBase,
      fontWeight: FontWeight.w500,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeBase** - 16px
  TextStyle buttonLargeBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeBase,
      fontWeight: FontWeight.w600,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeLG** - 19px
  TextStyle bodyRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeLG,
      fontWeight: FontWeight.w500,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeLG** - 19px
  TextStyle bodyBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeLG,
      fontWeight: FontWeight.w600,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeLG** - 19px
  TextStyle inputLargeRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeLG,
      fontWeight: FontWeight.w500,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeLG** - 19px
  TextStyle inputLargeBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeLG,
      fontWeight: FontWeight.w600,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeXL** - 22px
  TextStyle buttonXLargeRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeXL,
      fontWeight: FontWeight.w500,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSizeXL** - 22px
  TextStyle buttonXLargeBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeXL,
      fontWeight: FontWeight.w600,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSize2XL** - 28px
  TextStyle leadRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSize2XL,
      fontWeight: FontWeight.w500,
      height: lineHeightsBodyDefault,
    );
  }

  /// **fontSize2XL** - 28px
  TextStyle leadBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSize2XL,
      fontWeight: FontWeight.w600,
      height: lineHeightsBodyDefault,
    );
  }
}

class Headline {
  const Headline();

  /// **fontSizeXL** - ~22px
  TextStyle headline5Regular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSizeXL,
      fontWeight: FontWeight.w700,
      height: lineHeightsHeadlinesXl,
      letterSpacing: letterSpacingHeadlines,
    );
  }

  /// **fontSizeXL** - ~22px
  TextStyle headline5Bold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSizeXL,
      fontWeight: FontWeight.w800,
      letterSpacing: letterSpacingHeadlines,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize3XL** - ~34px
  TextStyle headline4Regular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize3XL,
      fontWeight: FontWeight.w700,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize3XL** - ~34px
  TextStyle headline4Bold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize3XL,
      fontWeight: FontWeight.w800,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize4XL** - ~41px
  TextStyle headline3Regular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize4XL,
      fontWeight: FontWeight.w700,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize4XL** - ~41px
  TextStyle headline3Bold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize4XL,
      fontWeight: FontWeight.w800,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize5XL** - ~49px
  TextStyle headline2Regular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize5XL,
      fontWeight: FontWeight.w700,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize5XL** - ~49px
  TextStyle headline2Bold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize5XL,
      fontWeight: FontWeight.w800,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize6XL** - ~58px
  TextStyle headline1Regular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize6XL,
      fontWeight: FontWeight.w700,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize6XL** - ~58px
  TextStyle headline1Bold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize6XL,
      fontWeight: FontWeight.w800,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize7XL** - ~69px
  TextStyle displayRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize7XL,
      fontWeight: FontWeight.w700,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize7XL** - ~69px
  TextStyle displayBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize7XL,
      fontWeight: FontWeight.w800,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize8XL** - ~82px
  TextStyle heroRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize8XL,
      fontWeight: FontWeight.w700,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize8XL** - ~82px
  TextStyle heroBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize8XL,
      fontWeight: FontWeight.w800,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize9XL** - ~98px
  TextStyle uberRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize9XL,
      fontWeight: FontWeight.w700,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize9XL** - ~98px
  TextStyle uberBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize9XL,
      fontWeight: FontWeight.w800,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize10XL** - ~117px
  TextStyle colossusRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize10XL,
      fontWeight: FontWeight.w700,
      height: lineHeightsHeadlinesXl,
    );
  }

  /// **fontSize10XL** - ~117px
  TextStyle colossusBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesHeadlines,
      package: _package,
      fontSize: fontSize10XL,
      fontWeight: FontWeight.w800,
      height: lineHeightsHeadlinesXl,
    );
  }
}

/// Font families
const String fontFamiliesHeadlines = 'Wavehaus';
const String fontFamiliesBody = 'Wavehaus';

/// Line Height
const double lineHeightsHeadlinesXl = 1.1;
const double lineHeightsHeadlinesLg = 1.1;
const double lineHeightsHeadlinesFefault = 1.1;
const double lineHeightsHeadlinesSm = 1.3;
const double lineHeightsBodyRelaxed = 1.75;
const double lineHeightsBodyDefault = 1.5;

const double letterSpacingHeadlines = kIsWeb ? 0.5 : -1;

/// Font Sizes
const double fontSizeBase = 16;
const double fontSizeScale = 1.2;

/// ~ 9px
const double fontSizeXXS = fontSizeXS / fontSizeScale;

/// ~ 11px
const double fontSizeXS = fontSizeSM / fontSizeScale;

/// ~ 13px
const double fontSizeSM = fontSizeBase / fontSizeScale;

/// ~ 19px
const double fontSizeLG = fontSizeBase * fontSizeScale;

/// ~ 22px
const double fontSizeXL = fontSizeLG * fontSizeScale;

/// ~ 28px
const double fontSize2XL = fontSizeXL * fontSizeScale;

/// ~ 34px
const double fontSize3XL = fontSize2XL * fontSizeScale;

/// ~ 41px
const double fontSize4XL = fontSize3XL * fontSizeScale;

/// ~ 49px
const double fontSize5XL = fontSize4XL * fontSizeScale;

/// ~ 58px
const double fontSize6XL = fontSize5XL * fontSizeScale;

/// ~ 69px
const double fontSize7XL = fontSize6XL * fontSizeScale;

/// ~ 82px
const double fontSize8XL = fontSize7XL * fontSizeScale;

/// ~ 98px
const double fontSize9XL = fontSize8XL * fontSizeScale;

/// ~ 117px
const double fontSize10XL = fontSize9XL * fontSizeScale;
