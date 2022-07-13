import 'package:ardrive/utils/split_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitTranslationsWithMultipleStyles method', () {
    Widget defaultFactory(String text) => Text(text);
    Widget anchorFactory(String text) => TextButton(
          child: Text(text),
          onPressed: () => print('PRESS'),
        );

    test('returns the expected type of widgets in order', () {
      final widgetsJA = splitTranslationsWithMultipleStyles(
        originalText: '利用規約と ArDrive の プライバシーポリシーに同意します',
        defaultMapper: defaultFactory,
        parts: {'ArDrive の プライバシーポリシー': anchorFactory},
      );
      expect(widgetsJA[0] is Text, true);
      expect(widgetsJA[1] is TextButton, true);
      expect(widgetsJA[2] is Text, true);
      expect(widgetsJA.length, 3);

      final widgetsEN = splitTranslationsWithMultipleStyles(
        originalText:
            'I agree to the ArDrive terms of service and privacy policy',
        defaultMapper: defaultFactory,
        parts: {
          'ArDrive terms of service and privacy policy': anchorFactory,
        },
      );
      expect(widgetsEN[0] is Text, true);
      expect(widgetsEN[1] is TextButton, true);
      expect(widgetsEN.length, 2);
    });

    test('puts separators between each part if specified', () {
      final widgetsEN = splitTranslationsWithMultipleStyles<Widget>(
        originalText:
            'I agree to the ArDrive terms of service and privacy policy',
        defaultMapper: defaultFactory,
        parts: {
          'ArDrive terms of service and privacy policy': anchorFactory,
        },
        separator: const SizedBox(height: 32, width: 32),
      );
      expect(widgetsEN[0] is Text, true);
      expect(widgetsEN[1] is SizedBox, true);
      expect(widgetsEN[2] is TextButton, true);
      expect(widgetsEN.length, 3);
    });
  });
}
