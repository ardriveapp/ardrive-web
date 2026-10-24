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

        // WCAG AA: 4.5:1 for text, 3:1 for icons and other graphics.
        test('$status body text is readable on its container', () {
          expect(
              _contrast(tokens.textHigh, container), greaterThanOrEqualTo(4.5));
        });

        test('$status icon stands out from its container', () {
          expect(_contrast(fg, container), greaterThanOrEqualTo(3));
        });
      });
    });
  }
}
