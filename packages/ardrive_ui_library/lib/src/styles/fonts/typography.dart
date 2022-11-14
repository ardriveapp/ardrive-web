import 'package:flutter/material.dart';

const String _package = 'ardrive_ui_library';

class ArDriveTypography {
  static Body body = const Body();
  static Headline headline = const Headline();
}

class Body {
  const Body();

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

  TextStyle captionBold({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeLG,
      fontWeight: FontWeight.w600,
      height: lineHeightsBodyDefault,
    );
  }

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

  TextStyle buttonNormalRegular({Color? color}) {
    return TextStyle(
      color: color,
      fontFamily: fontFamiliesBody,
      package: _package,
      fontSize: fontSizeSM,
      fontWeight: FontWeight.w600,
      height: lineHeightsBodyDefault,
    );
  }

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
}

class Headline {
  const Headline();

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

const double letterSpacingHeadlines = -1;

/// Font Sizes
const double fontSizeBase = 16;
const double fontSizeScale = 1.2;
const double fontSizeXXS = fontSizeXS / fontSizeScale;
const double fontSizeXS = fontSizeSM / fontSizeScale;
const double fontSizeSM = fontSizeBase / fontSizeScale;
const double fontSizeLG = fontSizeBase * fontSizeScale;
const double fontSizeXL = fontSizeLG * fontSizeScale;
const double fontSize2XL = fontSizeXL * fontSizeScale;
const double fontSize3XL = fontSize2XL * fontSizeScale;
const double fontSize4XL = fontSize3XL * fontSizeScale;
const double fontSize5XL = fontSize4XL * fontSizeScale;
const double fontSize6XL = fontSize5XL * fontSizeScale;
const double fontSize7XL = fontSize6XL * fontSizeScale;
const double fontSize8XL = fontSize7XL * fontSizeScale;
const double fontSize9XL = fontSize8XL * fontSizeScale;
const double fontSize10XL = fontSize9XL * fontSizeScale;
