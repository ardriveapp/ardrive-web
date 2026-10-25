import 'package:flutter/material.dart';

class Primitives {
  Primitives({
    required this.solidRed100,
    required this.solidRed200,
    required this.solidRed300,
    required this.solidRed400,
    required this.solidRed500,
    required this.solidRed600,
    required this.solidRed700,
    required this.solidRed800,
    required this.solidRed900,
    required this.solidRed1000,
    required this.solidRed1100,
    required this.solidGrey50,
    required this.solidGrey100,
    required this.solidGrey200,
    required this.solidGrey300,
    required this.solidGrey400,
    required this.solidGrey500,
    required this.solidGrey600,
    required this.solidGrey700,
    required this.solidGrey800,
    required this.solidGrey900,
    required this.solidGrey1000,
    required this.solidGrey1100,
    required this.transparent100_64,
    required this.transparent100_32,
    required this.transparent100_16,
    required this.transparent100_12,
    required this.transparent100_8,
    required this.transparent100_4,
    required this.transparent900_64,
    required this.transparent900_32,
    required this.transparent900_16,
    required this.transparent900_12,
    required this.transparent900_8,
    required this.transparent900_4,
  });

  factory Primitives.darkMode() {
    return Primitives(
        solidRed100: const Color(0xff150203),
        solidRed200: const Color(0xff260406),
        solidRed300: const Color(0xff4d080c),
        solidRed400: const Color(0xff730d12),
        solidRed500: const Color(0xff9a1118),
        solidRed600: const Color(0xffc0151e),
        solidRed700: const Color(0xffd31721),
        solidRed800: const Color(0xffd42c35),
        solidRed900: const Color(0xffdf565d),
        solidRed1000: const Color(0xffe78086),
        solidRed1100: const Color(0xfff7d5d7),
        solidGrey50: const Color(0xffffffff),
        solidGrey100: const Color(0xffe0e0e0),
        solidGrey200: const Color(0xffa6a6a6),
        solidGrey300: const Color(0xff7d7d7d),
        solidGrey400: const Color(0xff5e5e5e),
        solidGrey500: const Color(0xff424241),
        solidGrey600: const Color(0xff2e2e2e),
        solidGrey700: const Color(0xff171717),
        solidGrey800: const Color(0xff121212),
        solidGrey900: const Color(0xff0d0d0d),
        solidGrey1000: const Color(0xff080808),
        solidGrey1100: const Color(0xff000000),
        transparent100_64: const Color(0xa3ededed),
        transparent100_32: const Color(0x51ededed),
        transparent100_16: const Color(0x28ededed),
        transparent100_12: const Color(0x1eededed),
        transparent100_8: const Color(0x14ededed),
        transparent100_4: const Color(0x0aededed),
        transparent900_64: const Color(0xa3080808),
        transparent900_32: const Color(0x51080808),
        transparent900_16: const Color(0x28080808),
        transparent900_12: const Color(0x1e080808),
        transparent900_8: const Color(0x14080808),
        transparent900_4: const Color(0x0a080808));
  }

  factory Primitives.lightMode() {
    return Primitives(
        solidRed100: const Color(0xfffcf9fa),
        solidRed200: const Color(0xfff7d2d4),
        solidRed300: const Color(0xfff2b6b9),
        solidRed400: const Color(0xffed9a9f),
        solidRed500: const Color(0xffe78086),
        solidRed600: const Color(0xffdf565d),
        solidRed700: const Color(0xffd31721),
        solidRed800: const Color(0xffd42c35),
        solidRed900: const Color(0xffc0151e),
        solidRed1000: const Color(0xff4d080c),
        solidRed1100: const Color(0xff150203),
        solidGrey50: const Color(0xFFF7F7F7),
        solidGrey100: const Color(0xFFEBEBEB),
        solidGrey200: const Color(0xFFDEDEDE),
        solidGrey300: const Color(0xFFCECECE),
        solidGrey400: const Color(0xFFBABABA),
        solidGrey500: const Color(0xFF8A8A8A),
        solidGrey600: const Color(0xFF666666),
        solidGrey700: const Color(0xFF4F4F4F),
        solidGrey800: const Color(0xFF3B3B3B),
        solidGrey900: const Color(0xFF262626),
        solidGrey1000: const Color(0xFF1F1F1F),
        solidGrey1100: const Color(0xFF000000),
        transparent100_64: const Color(0xa3bababa),
        transparent100_32: const Color(0x51bababa),
        transparent100_16: const Color(0x28bababa),
        transparent100_12: const Color(0x1ebababa),
        transparent100_8: const Color(0x14bababa),
        transparent100_4: const Color(0x0abababa),
        transparent900_64: const Color(0xa3080808),
        transparent900_32: const Color(0x51080808),
        transparent900_16: const Color(0x28080808),
        transparent900_12: const Color(0x1e080808),
        transparent900_8: const Color(0x14080808),
        transparent900_4: const Color(0x0a080808));
  }

  final Color solidRed100;
  final Color solidRed200;
  final Color solidRed300;
  final Color solidRed400;
  final Color solidRed500;
  final Color solidRed600;
  final Color solidRed700;
  final Color solidRed800;
  final Color solidRed900;
  final Color solidRed1000;
  final Color solidRed1100;

  final Color solidGrey50;
  final Color solidGrey100;
  final Color solidGrey200;
  final Color solidGrey300;
  final Color solidGrey400;
  final Color solidGrey500;
  final Color solidGrey600;
  final Color solidGrey700;
  final Color solidGrey800;
  final Color solidGrey900;
  final Color solidGrey1000;
  final Color solidGrey1100;

  final Color transparent100_64;
  final Color transparent100_32;
  final Color transparent100_16;
  final Color transparent100_12;
  final Color transparent100_8;
  final Color transparent100_4;

  final Color transparent900_64;
  final Color transparent900_32;
  final Color transparent900_16;
  final Color transparent900_12;
  final Color transparent900_8;
  final Color transparent900_4;
}

class ArDriveColorTokens {
  ArDriveColorTokens({
    required this.primitives,
    required this.containerL0,
    required this.containerL1,
    required this.containerL2,
    required this.containerL3,
    required this.containerRed,
    required this.containerRaised,
    required this.textHigh,
    required this.textMid,
    required this.textLow,
    required this.textXLow,
    required this.textLink,
    required this.textOnPrimary,
    required this.textRed,
    required this.strokeLow,
    required this.strokeMid,
    required this.strokeHigh,
    required this.strokeRed,
    required this.buttonPrimaryDefault,
    required this.buttonPrimaryHover,
    required this.buttonPrimaryPress,
    required this.buttonDisabled,
    required this.buttonSecondaryDefault,
    required this.buttonSecondaryHover,
    required this.buttonSecondaryPress,
    required this.buttonOutlineDefault,
    required this.buttonOutlineHover,
    required this.buttonOutlinePress,
    required this.inputDefault,
    required this.inputDisabled,
    required this.iconLow,
    required this.iconMid,
    required this.iconHigh,
    required this.statusInfoFg,
    required this.statusInfoContainer,
    required this.statusInfoStroke,
    required this.statusWarningFg,
    required this.statusWarningContainer,
    required this.statusWarningStroke,
    required this.statusErrorFg,
    required this.statusErrorContainer,
    required this.statusErrorStroke,
    required this.statusSuccessFg,
    required this.statusSuccessContainer,
    required this.statusSuccessStroke,
  });

  factory ArDriveColorTokens.darkMode() {
    var primitives = Primitives.darkMode();

    return ArDriveColorTokens(
      primitives: primitives,
      containerL0: primitives.solidGrey1000,
      containerL1: primitives.solidGrey900,
      containerL2: primitives.solidGrey800,
      containerL3: primitives.solidGrey700,
      containerRed: primitives.solidRed700,
      containerRaised: const Color(0xff1f1f1f),
      textHigh: primitives.solidGrey100,
      textMid: primitives.solidGrey200,
      textLow: primitives.solidGrey300,
      textXLow: primitives.solidGrey500,
      textLink: primitives.solidGrey200,
      textOnPrimary: primitives.solidGrey50,
      textRed: primitives.solidRed800,
      strokeLow: primitives.transparent100_8,
      strokeMid: primitives.transparent100_12,
      strokeHigh: primitives.transparent100_16,
      strokeRed: primitives.solidRed600,
      buttonPrimaryDefault: primitives.solidRed700,
      buttonPrimaryHover: primitives.solidRed600,
      buttonPrimaryPress: primitives.solidRed500,
      buttonDisabled: primitives.solidGrey600,
      // Translucent, so a secondary button is a shade lighter than whatever
      // it sits on. It was a solid grey700: the colour of a dialog
      // (containerL3), where Cancel had no edge at all.
      buttonSecondaryDefault: primitives.transparent100_8,
      buttonSecondaryHover: primitives.transparent100_12,
      buttonSecondaryPress: primitives.transparent100_16,
      buttonOutlineDefault: Colors.transparent,
      buttonOutlineHover: primitives.solidGrey600,
      buttonOutlinePress: primitives.solidGrey500,
      inputDefault: primitives.solidGrey900,
      inputDisabled: primitives.solidGrey800,
      iconLow: primitives.solidGrey400,
      iconMid: primitives.solidGrey200,
      iconHigh: primitives.solidGrey50,
      statusInfoFg: const Color(0xff8b98f9),
      statusInfoContainer: const Color(0xff111833),
      statusInfoStroke: const Color(0xff253293),
      statusWarningFg: const Color(0xffffcf74),
      statusWarningContainer: const Color(0xff33250b),
      statusWarningStroke: const Color(0xff664b16),
      statusErrorFg: const Color(0xffe95c7b),
      statusErrorContainer: const Color(0xff2d040d),
      statusErrorStroke: const Color(0xff59091a),
      statusSuccessFg: const Color(0xff5dc389),
      statusSuccessContainer: const Color(0xff052211),
      statusSuccessStroke: const Color(0xff0a4423),
    );
  }

  factory ArDriveColorTokens.lightMode() {
    var primitives = Primitives.lightMode();

    return ArDriveColorTokens(
      primitives: primitives,
      containerL0: primitives.solidGrey50,
      containerL1: primitives.solidGrey100,
      containerL2: primitives.solidGrey200,
      containerL3: primitives.solidGrey200,
      containerRed: primitives.solidRed700,
      containerRaised: const Color(0xffffffff),
      textHigh: primitives.solidGrey800,
      textMid: primitives.solidGrey700,
      textLow: primitives.solidGrey600,
      textXLow: primitives.solidGrey500,
      textLink: primitives.solidGrey700,
      textOnPrimary: primitives.solidGrey50,
      textRed: primitives.solidRed800,
      strokeLow: primitives.transparent900_12,
      strokeMid: primitives.transparent900_16,
      strokeHigh: primitives.solidGrey300,
      strokeRed: primitives.solidRed600,
      buttonPrimaryDefault: primitives.solidRed700,
      buttonPrimaryHover: primitives.solidRed600,
      buttonPrimaryPress: primitives.solidRed500,
      buttonDisabled: primitives.solidGrey300,
      // Translucent, so a secondary button is a shade darker than whatever
      // it sits on. It was a solid grey100: the colour of a card
      // (containerL1), where the button disappeared.
      buttonSecondaryDefault: primitives.transparent900_8,
      buttonSecondaryHover: primitives.transparent900_12,
      buttonSecondaryPress: primitives.transparent900_16,
      buttonOutlineDefault: Colors.transparent,
      buttonOutlineHover: primitives.transparent900_12,
      buttonOutlinePress: primitives.transparent900_16,
      inputDefault: primitives.solidGrey100,
      inputDisabled: primitives.solidGrey300,
      iconLow: primitives.solidGrey500,
      iconMid: primitives.solidGrey600,
      iconHigh: primitives.solidGrey700,
      statusInfoFg: const Color(0xff3142c4),
      statusInfoContainer: const Color(0xffeceefe),
      statusInfoStroke: const Color(0xffb1bafb),
      statusWarningFg: const Color(0xff664b16),
      statusWarningContainer: const Color(0xfffff8eb),
      statusWarningStroke: const Color(0xffffe4af),
      statusErrorFg: const Color(0xffc0151e),
      statusErrorContainer: const Color(0xfffdf1f4),
      statusErrorStroke: const Color(0xfff9d0d9),
      statusSuccessFg: const Color(0xff11763d),
      statusSuccessContainer: const Color(0xfff4fbf7),
      statusSuccessStroke: const Color(0xffd1eedd),
    );
  }

  final Primitives primitives;
  final Color containerL0;
  final Color containerL1;
  final Color containerL2;
  final Color containerL3;
  final Color containerRed;

  /// A card raised one step above the panel or page it sits on, in both
  /// themes: white in light, a lifted grey in dark. The L0-L3 levels can't
  /// say that - L0 is the lightest in the light theme and the darkest in the
  /// dark one.
  final Color containerRaised;
  final Color textHigh;
  final Color textMid;
  final Color textLow;
  final Color textXLow;
  final Color textLink;
  final Color textOnPrimary;
  final Color textRed;
  final Color strokeLow;
  final Color strokeMid;
  final Color strokeHigh;
  final Color strokeRed;
  final Color buttonPrimaryDefault;
  final Color buttonPrimaryHover;
  final Color buttonPrimaryPress;
  final Color buttonDisabled;
  final Color buttonSecondaryDefault;
  final Color buttonSecondaryHover;
  final Color buttonSecondaryPress;
  final Color buttonOutlineDefault;
  final Color buttonOutlineHover;
  final Color buttonOutlinePress;
  final Color inputDefault;
  final Color inputDisabled;
  final Color iconLow;
  final Color iconMid;
  final Color iconHigh;

  /// Status colours, for notices and other messages that carry a meaning:
  /// info, warning, error and success. Fg colours the icon and any emphasis,
  /// Container fills the surface behind it and Stroke draws its edge. Body
  /// text on a status container stays [textHigh].
  final Color statusInfoFg;
  final Color statusInfoContainer;
  final Color statusInfoStroke;
  final Color statusWarningFg;
  final Color statusWarningContainer;
  final Color statusWarningStroke;
  final Color statusErrorFg;
  final Color statusErrorContainer;
  final Color statusErrorStroke;
  final Color statusSuccessFg;
  final Color statusSuccessContainer;
  final Color statusSuccessStroke;
}
