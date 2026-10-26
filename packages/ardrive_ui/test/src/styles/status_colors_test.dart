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

void main() {
  for (final (name, tokens) in [
    ('dark', ArDriveColorTokens.darkMode()),
    ('light', ArDriveColorTokens.lightMode()),
  ]) {
    final statuses = {
      'info': (tokens.statusInfoFg, tokens.statusInfoContainer),
      'warning': (tokens.statusWarningFg, tokens.statusWarningContainer),
      'error': (tokens.statusErrorFg, tokens.statusErrorContainer),
      'success': (tokens.statusSuccessFg, tokens.statusSuccessContainer),
    };

    group('$name status colours', () {
      statuses.forEach((status, colors) {
        final (fg, container) = colors;

        // WCAG AA: 4.5:1 for text.
        test('$status body text is readable on its container', () {
          expect(
              _contrast(tokens.textHigh, container), greaterThanOrEqualTo(4.5));
        });

        // Fg also colours error and success text, such as a field's error
        // message, so it is held to the text ratio.
        test('$status colour reads as text on its container', () {
          expect(_contrast(fg, container), greaterThanOrEqualTo(4.5));
        });
      });

      // The brand palette has no warning colour: a warning is neutral and
      // its icon carries the meaning.
      test('warning is neutral', () {
        for (final c in [
          tokens.statusWarningFg,
          tokens.statusWarningContainer,
          tokens.statusWarningStroke,
        ]) {
          expect(c.red == c.green && c.green == c.blue, isTrue,
              reason: '$c is not a grey');
        }
      });

      // Nor an error colour of its own: errors use the brand reds.
      test('error comes from the brand reds', () {
        final p = tokens.primitives;
        final reds = [
          p.solidRed100,
          p.solidRed200,
          p.solidRed300,
          p.solidRed400,
          p.solidRed500,
          p.solidRed600,
          p.solidRed700,
          p.solidRed800,
          p.solidRed900,
          p.solidRed1000,
          p.solidRed1100,
        ];
        expect(reds, contains(tokens.statusErrorFg));
        expect(reds, contains(tokens.statusErrorContainer));
        expect(reds, contains(tokens.statusErrorStroke));
      });
    });
  }
}
