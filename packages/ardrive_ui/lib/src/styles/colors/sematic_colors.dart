import 'package:ardrive_ui/src/styles/colors/global_colors.dart';
import 'package:flutter/material.dart';

class ArDriveColors {
  ArDriveColors({
    Color? themeFgDefault,
    Color? themeFgMuted,
    Color? themeFgSubtle,
    Color? themeFgOnAccent,
    Color? themeFgOnDisabled,
    Color? themeFgDisabled,
    Color? themeBgSurface,
    Color? themeGbMuted,
    Color? themeBgSubtle,
    Color? themeBgCanvas,
    Color? themeAccentBrand,
    Color? themeAccentMuted,
    Color? themeWarningFg,
    Color? themeWarningEmphasis,
    Color? themeWarningMuted,
    Color? themeWarningSubtle,
    Color? themeWarningOnWarning,
    Color? themeErrorFg,
    Color? themeErrorMuted,
    Color? themeErrorSubtle,
    Color? themeErrorOnError,
    Color? themeInfoFb,
    Color? themeInfoEmphasis,
    Color? themeInfoMuted,
    Color? themeInfoSubtle,
    Color? themeInfoOnInfo,
    Color? themeSuccessFb,
    Color? themeSuccessEmphasis,
    Color? themeSuccessMuted,
    Color? themeSuccessSubtle,
    Color? themeSuccessOnSuccess,
    Color? themeInputBackground,
    Color? themeInputText,
    Color? themeInputPlaceholder,
    Color? themeInputBorderDisabled,
    Color? themeInputFbDisabled,
    Color? themeBorderDefault,
    Color? themeOverlayBackground,
    Color? themeAccentDefault,
    Color? themeAccentDisabled,
    Color? themeAccentSubtle,
    Color? themeInputBorderDefault,
    Color? themeErrorOnEmphasis,
    Color? themeAccentEmphasis,
    Color? themeErrorDefault,
    Color? themeSuccessDefault,
    Color? shadow,
  }) {
    this.themeFgDefault = themeFgDefault ?? white;
    this.themeFgMuted = themeFgMuted ?? grey.shade200;
    this.themeFgSubtle = themeFgSubtle ?? grey.shade500;
    this.themeFgOnAccent = themeFgOnAccent ?? white;
    this.themeFgOnDisabled = themeFgOnDisabled ?? grey.shade300;
    this.themeFgDisabled = themeFgDisabled ?? grey.shade600;
    this.themeBgSurface =
        themeBgSurface ?? const Color(0xff1F1F1F); // grey.shade960
    this.themeGbMuted = themeGbMuted ?? grey.shade600;
    this.themeBgSubtle = themeBgSubtle ?? grey.shade900;
    this.themeBgCanvas =
        themeBgCanvas ?? const Color(0xff171717); // grey.shade950;
    this.themeAccentBrand = themeAccentBrand ?? red.shade500;
    this.themeAccentMuted = themeAccentMuted ?? blue.shade400;
    this.themeWarningFg = themeWarningFg ?? yellow.shade400;
    this.themeWarningEmphasis = themeWarningEmphasis ?? yellow.shade500;
    this.themeWarningMuted = themeWarningMuted ?? yellow.shade600;
    this.themeWarningSubtle = themeWarningSubtle ?? yellow.shade800;
    this.themeWarningOnWarning = themeWarningOnWarning ?? black;
    this.themeErrorFg = themeErrorFg ?? red.shade400;
    this.themeErrorMuted = themeErrorMuted ?? red.shade600;
    this.themeErrorSubtle = themeErrorSubtle ?? red.shade800;
    this.themeErrorOnError = themeErrorOnError ?? white;
    this.themeInfoFb = themeInfoFb ?? blue.shade600;
    this.themeInfoEmphasis = themeInfoEmphasis ?? blue.shade500;
    this.themeInfoMuted = themeInfoMuted ?? blue.shade300;
    this.themeInfoSubtle = themeInfoSubtle ?? blue.shade100;
    this.themeInfoOnInfo = themeInfoOnInfo ?? white;
    this.themeSuccessFb = themeSuccessFb ?? green.shade400;
    this.themeSuccessEmphasis = themeSuccessEmphasis ?? green.shade500;
    this.themeSuccessMuted = themeSuccessMuted ?? green.shade600;
    this.themeSuccessSubtle = themeSuccessSubtle ?? green.shade800;
    this.themeSuccessOnSuccess = themeSuccessOnSuccess ?? white;
    this.themeInputBackground = themeInputBackground ?? white;
    this.themeInputText = themeInputText ?? grey.shade800;
    this.themeInputPlaceholder = themeInputPlaceholder ?? grey.shade500;
    this.themeInputBorderDisabled = themeInputBorderDisabled ?? grey.shade200;
    this.themeInputFbDisabled = themeInputFbDisabled ?? grey.shade300;
    this.themeBorderDefault = themeBorderDefault ?? this.themeBgSubtle;
    this.themeOverlayBackground = themeOverlayBackground ?? black;
    this.themeAccentDefault = blue;
    this.themeAccentDisabled = grey.shade600;
    this.themeAccentSubtle = themeAccentSubtle ?? blue.shade900;
    this.themeInputBorderDefault = themeInputBorderDefault ?? grey.shade300;
    this.themeErrorOnEmphasis = themeErrorOnEmphasis ?? red;
    this.themeAccentEmphasis = themeAccentEmphasis ?? blue.shade600;
    this.themeErrorDefault = themeErrorDefault ?? red.shade400;
    this.themeSuccessDefault = themeSuccessDefault ?? green.shade400;
    this.shadow = shadow ?? shadowColor;
  }

  factory ArDriveColors.light() => ArDriveColors(
        themeFgDefault: black,
        themeFgMuted: grey.shade700,
        themeFgSubtle: grey.shade500,
        themeFgOnAccent: white,
        themeFgOnDisabled: grey.shade600,
        themeFgDisabled: grey.shade400,
        themeBgSurface: white,
        themeGbMuted: grey.shade300,
        themeBgSubtle: grey.shade200,
        themeBgCanvas: grey.shade50,
        themeWarningFg: yellow.shade600,
        themeWarningEmphasis: yellow.shade500,
        themeWarningMuted: yellow.shade300,
        themeWarningSubtle: yellow.shade100,
        themeWarningOnWarning: black,
        themeErrorFg: red.shade600,
        themeErrorMuted: red.shade400,
        themeErrorSubtle: red.shade100,
        themeErrorOnError: white,
        themeOverlayBackground: black,
        themeAccentDefault: grey.shade400,
        themeAccentSubtle: blue.shade50,
        shadow: shadowColorLight,
      );

  factory ArDriveColors.dark() => ArDriveColors();

  /// Foreground
  late Color themeFgDefault;
  late Color themeFgMuted;
  late Color themeFgSubtle;
  late Color themeFgOnAccent;
  late Color themeFgOnDisabled;
  late Color themeFgDisabled;

  /// Background
  late Color themeBgSurface;
  late Color themeGbMuted;
  late Color themeBgSubtle;
  late Color themeBgCanvas;

  /// Accent
  late Color themeAccentBrand;
  late Color themeAccentDefault;
  late Color themeAccentDisabled;
  late Color themeAccentMuted;
  late Color themeAccentSubtle;
  late Color themeAccentEmphasis;

  /// Warning
  late Color themeWarningFg;
  late Color themeWarningEmphasis;
  late Color themeWarningMuted;
  late Color themeWarningSubtle;
  late Color themeWarningOnWarning;

  /// Error
  late Color themeErrorFg;
  late Color themeErrorMuted;
  late Color themeErrorSubtle;
  late Color themeErrorOnError;
  late Color themeErrorOnEmphasis;
  late Color themeErrorDefault;

  /// Info
  late Color themeInfoFb;
  late Color themeInfoEmphasis;
  late Color themeInfoMuted;
  late Color themeInfoSubtle;
  late Color themeInfoOnInfo;

  /// Success
  late Color themeSuccessFb;
  late Color themeSuccessEmphasis;
  late Color themeSuccessMuted;
  late Color themeSuccessSubtle;
  late Color themeSuccessOnSuccess;
  late Color themeSuccessDefault;

  /// Input
  late Color themeInputBackground;
  late Color themeInputText;
  late Color themeInputPlaceholder;
  late Color themeInputBorderDisabled;
  late Color themeInputFbDisabled;
  late Color themeInputBorderDefault;

  /// Border
  late Color themeBorderDefault;

  /// Overlay
  late Color themeOverlayBackground;

  /// Shadow
  late Color shadow;
}
