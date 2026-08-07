import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The recipient landing page's foregrounds, picked so that every one of them
/// clears WCAG AA - 4.5:1 for text, 3:1 for anything that carries meaning
/// without text - in *both* themes.
///
/// The design system's own tokens do not, because several of them are the same
/// colour in the light theme as in the dark one:
///
/// * `themeFgSubtle` is `grey.500` either way. Against the dark surface that is
///   ~6.2:1, but against the light one it is ~2.7:1 - and this page is mostly
///   caption text.
/// * `themeSuccessDefault` is `green.400` either way, so the Verified badge
///   reads at ~2.2:1 on white.
/// * `themeInfoSubtle` - the freshness banner's background - is `blue.100`
///   either way, while the text on it is `themeFgDefault`. In the dark theme
///   that is white on pale blue: ~1.2:1, which is not a contrast problem so
///   much as an invisible banner.
///
/// Restyling those tokens would change every screen in the app. This page picks
/// the token that passes for the theme it is actually in, and never a literal
/// colour.
///
/// Every recipient arrives here from somebody else's link, with no account, no
/// stored theme preference and no second route to the file. It is the one page
/// in the app that has to be readable first time, for everybody.
class SharedFileColors {
  const SharedFileColors._();

  /// Caption and secondary text: sizes, dates, drawer headers, the labels in
  /// the details drawer, and the icons of the message states.
  ///
  /// Light: `themeFgMuted` (`grey.700`), ~5.9:1 on the card and on the page.
  /// Dark: `themeFgSubtle` (`grey.500`), ~6.2:1 on the card and ~7.0:1 on the
  /// page.
  static Color subtle(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return _isLight(context) ? colors.themeFgMuted : colors.themeFgSubtle;
  }

  /// The Verified badge.
  ///
  /// Light: `themeSuccessMuted` (`green.600`), ~5.7:1 on white.
  /// Dark: `themeSuccessDefault` (`green.400`), ~7.6:1 on the card.
  static Color success(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return _isLight(context)
        ? colors.themeSuccessMuted
        : colors.themeSuccessDefault;
  }

  /// The background of the version notices.
  ///
  /// `themeInfoSubtle` is a fixed pale blue in both themes and cannot carry
  /// `themeFgDefault` text in the dark one, so the notice is built on the
  /// theme's own subtle background instead. The blue is not what makes it a
  /// notice; the icon and the sentence are.
  static Color noticeBackground(BuildContext context) =>
      ArDriveTheme.of(context).themeData.colors.themeBgSubtle;

  /// Text and icon on [noticeBackground]: ~17.9:1 light, ~12.8:1 dark.
  static Color onNotice(BuildContext context) =>
      ArDriveTheme.of(context).themeData.colors.themeFgDefault;

  // TODO: replace with ArDriveTheme .isLight method
  static bool _isLight(BuildContext context) =>
      ArDriveTheme.of(context).themeData.name == 'light';
}
