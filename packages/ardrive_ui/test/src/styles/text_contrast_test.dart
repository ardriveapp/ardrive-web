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

/// The spec promises text that meets WCAG AA (4.5:1). Every text token is
/// held to it on every surface text sits on, from the page to a selected
/// table row: text-low once measured 3.39:1 on a selected row and the reds
/// under 3:1, which no single screen showed.
///
/// text-xlow is left out: it is for placeholders and disabled text, which AA
/// exempts.
void main() {
  for (final (name, theme) in [
    ('dark', ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode())),
    ('light', lightTheme()),
  ]) {
    final t = theme.colorTokens;
    final table = theme.tableTheme;
    final texts = {
      'text-high': t.textHigh,
      'text-mid': t.textMid,
      'text-low': t.textLow,
      'text-link': t.textLink,
      'text-red': t.textRed,
      'error': t.statusErrorFg,
    };
    final surfaces = {
      'page': theme.backgroundColor,
      'container-l0': t.containerL0,
      'container-l1': t.containerL1,
      'container-l2': t.containerL2,
      'container-l3': t.containerL3,
      'container-raised': t.containerRaised,
      'table': table.backgroundColor,
      'table cell': table.cellColor,
      'hovered row': table.hoverItemColor,
      'selected row': table.selectedItemColor,
    };

    group('$name text contrast', () {
      texts.forEach((textName, fg) {
        surfaces.forEach((surfaceName, bg) {
          test('$textName reads on $surfaceName', () {
            expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5));
          });
        });
      });

      // Disabled text is exempt from AA but must still be read: at least
      // 2:1 on a disabled button, a menu and a dialog, and dimmer than
      // text-low everywhere so a disabled item never looks enabled.
      for (final (surfaceName, bg) in [
        ('a disabled button', t.buttonDisabled),
        ('a menu', theme.dropdownTheme.backgroundColor),
        ('container-raised', t.containerRaised),
        ('a dialog', t.containerL3),
        ('the page', theme.backgroundColor),
      ]) {
        test('text-xlow can be read on $surfaceName', () {
          expect(_contrast(t.textXLow, bg), greaterThanOrEqualTo(2.0));
        });
        test('text-xlow is dimmer than text-low on $surfaceName', () {
          expect(_contrast(t.textXLow, bg), lessThan(_contrast(t.textLow, bg)));
        });
      }

      test('the page is container-l0', () {
        expect(theme.backgroundColor, t.containerL0);
      });

      // One red for text: an error, a failed sync and a destructive action
      // read as the same thing.
      test('text-red is the error colour', () {
        expect(t.textRed, t.statusErrorFg);
      });
    });
  }
}
