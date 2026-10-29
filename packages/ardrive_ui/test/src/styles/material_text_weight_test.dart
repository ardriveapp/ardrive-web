import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wavehaus declares Light as 400, Material's default weight, so a text style
/// the theme hands out must never be lighter than Book: Light is for large
/// figures only.
void main() {
  for (final (name, theme) in [
    ('light', lightTheme().materialThemeData),
    (
      'dark',
      ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode())
          .materialThemeData
    ),
  ]) {
    test('the $name theme draws no default text in Light', () {
      for (final textTheme in [theme.textTheme, theme.primaryTextTheme]) {
        for (final style in [
          textTheme.displayLarge,
          textTheme.displayMedium,
          textTheme.displaySmall,
          textTheme.headlineLarge,
          textTheme.headlineMedium,
          textTheme.headlineSmall,
          textTheme.titleLarge,
          textTheme.titleMedium,
          textTheme.titleSmall,
          textTheme.bodyLarge,
          textTheme.bodyMedium,
          textTheme.bodySmall,
          textTheme.labelLarge,
          textTheme.labelMedium,
          textTheme.labelSmall,
        ]) {
          expect(style!.fontWeight!.index,
              greaterThanOrEqualTo(FontWeight.w500.index));
        }
      }
    });
  }
}
