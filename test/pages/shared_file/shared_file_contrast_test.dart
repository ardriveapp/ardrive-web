import 'dart:math' as math;

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _luminance(Color c) {
  double channel(int v) {
    final s = v / 255;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4) as double;
  }

  return 0.2126 * channel(c.red) +
      0.7152 * channel(c.green) +
      0.0722 * channel(c.blue);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The shared file page is the one page every recipient reaches from someone
/// else's link, with no account and no theme preference, so each colour it
/// uses for text has to read first time: WCAG AA, 4.5:1, in both themes, on
/// the card and on the page behind it. It used to pick old-set colours per
/// theme to get there; the design system's tokens now do it themselves.
void main() {
  for (final (name, theme) in [
    ('light', lightTheme()),
    ('dark', ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode())),
  ]) {
    final tokens = theme.colorTokens;
    final grounds = {
      'card': tokens.containerRaised,
      'page': theme.tableTheme.backgroundColor,
    };

    group('$name theme', () {
      grounds.forEach((ground, background) {
        for (final (role, color) in [
          ('captions (textMid)', tokens.textMid),
          ('body (textHigh)', tokens.textHigh),
        ]) {
          test('$role on the $ground reads at AA', () {
            expect(
              _contrast(color, background),
              greaterThanOrEqualTo(4.5),
              reason: '$color on $background',
            );
          });
        }
      });

      test('the Verified badge reads at AA on the card', () {
        expect(
          _contrast(tokens.statusSuccessFg, tokens.containerRaised),
          greaterThanOrEqualTo(4.5),
        );
      });
    });
  }
}
