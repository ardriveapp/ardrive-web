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
    final containers = {
      'containerL0': tokens.containerL0,
      'containerL1': tokens.containerL1,
      'containerL2': tokens.containerL2,
      'containerL3': tokens.containerL3,
      'containerRaised': tokens.containerRaised,
    };

    group('$name secondary button', () {
      containers.forEach((level, container) {
        // A secondary button was a solid grey that equalled a card in light
        // mode and a dialog in dark mode, so it had no visible edge there.
        test('stands out on $level', () {
          final button =
              Color.alphaBlend(tokens.buttonSecondaryDefault, container);
          expect(_contrast(button, container), greaterThanOrEqualTo(1.12));
        });

        test('keeps its label readable on $level', () {
          final button =
              Color.alphaBlend(tokens.buttonSecondaryDefault, container);
          expect(_contrast(tokens.textLink, button), greaterThanOrEqualTo(4.5));
        });
      });
    });
  }
}
