import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Warm: red highest and green lowest, as in the styleguide's Gallery
/// #F1EFF0. A light translucent fill can round blue down to green.
bool _isWarm(Color c) =>
    c.red > c.green && c.red >= c.blue && c.blue >= c.green;
bool _isNeutral(Color c) => c.red == c.green && c.green == c.blue;

Color _over(Color top, Color bottom) => Color.alphaBlend(top, bottom);

void main() {
  final light = ArDriveColorTokens.lightMode();
  final dark = ArDriveColorTokens.darkMode();

  group('light theme', () {
    test('surface greys are warm', () {
      for (final (name, c) in [
        ('containerL0', light.containerL0),
        ('containerL1', light.containerL1),
        ('containerL2', light.containerL2),
        ('containerL3', light.containerL3),
        ('inputDefault', light.inputDefault),
        ('inputDisabled', light.inputDisabled),
        ('buttonDisabled', light.buttonDisabled),
        ('strokeHigh', light.strokeHigh),
      ]) {
        expect(_isWarm(c), isTrue, reason: '$name is $c');
      }
    });

    test('translucent fills and edges are warm over white', () {
      for (final (name, c) in [
        ('buttonSecondaryDefault', light.buttonSecondaryDefault),
        ('buttonSecondaryHover', light.buttonSecondaryHover),
        ('strokeLow', light.strokeLow),
        ('strokeMid', light.strokeMid),
      ]) {
        expect(_isWarm(_over(c, Colors.white)), isTrue, reason: name);
      }
    });

    test('text, icon and scrim greys stay neutral', () {
      for (final (name, c) in [
        ('textHigh', light.textHigh),
        ('textMid', light.textMid),
        ('textLow', light.textLow),
        ('textXLow', light.textXLow),
        ('iconLow', light.iconLow),
        ('iconMid', light.iconMid),
        ('iconHigh', light.iconHigh),
        ('transparent900_32', light.primitives.transparent900_32),
        ('transparent900_64', light.primitives.transparent900_64),
      ]) {
        expect(_isNeutral(c), isTrue, reason: '$name is $c');
      }
    });

    test('the table and menu surfaces match', () {
      final theme = lightTheme();
      for (final c in [
        theme.tableTheme.backgroundColor,
        theme.tableTheme.cellColor,
        theme.tableTheme.selectedItemColor,
        theme.dropdownTheme.backgroundColor,
        theme.dropdownTheme.hoverColor,
      ]) {
        expect(_isWarm(c), isTrue, reason: '$c');
      }
    });

    test('the old colour set\'s light greys match', () {
      final colors = ArDriveColors.light();
      expect(_isWarm(colors.themeBgSubtle), isTrue);
      expect(_isWarm(colors.themeGbMuted), isTrue);
    });
  });

  test('dark theme greys stay neutral', () {
    for (final c in [
      dark.containerL0,
      dark.containerL1,
      dark.containerL2,
      dark.containerL3,
      dark.inputDefault,
    ]) {
      expect(_isNeutral(c), isTrue, reason: '$c');
    }
  });

  test('light is Wavehaus 42 Light, the w400 face in the pubspec', () {
    expect(ArFontWeight.light.weight, FontWeight.w400);
  });
}
