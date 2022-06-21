import 'package:ardrive/utils/split_localizations.dart';
import 'package:ardrive/utils/text_partitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitTranslationsWithMultipleStyles method', () {
    final WidgetFactory defaultFactory = (String text) => Text(text);
    final WidgetFactory anchorFactory = (String text) => TextButton(
          child: Text(text),
          onPressed: () => print('PRESS'),
        );

    final partitionsJA =
        TextPartitions(wholeText: '利用規約と ArDrive の プライバシーポリシーに同意します');
    final partitionsEN = TextPartitions(
        wholeText:
            'I agree to the ArDrive terms of service and privacy policy');

    test('returns the expected type of widgets in order', () {
      final widgetsJA = splitTranslationsWithMultipleStyles(
          '利用規約と ArDrive の プライバシーポリシーに同意します',
          defaultFactory,
          {'ArDrive の プライバシーポリシー': anchorFactory});
      expect(widgetsJA[0] is Text, true);
      expect(widgetsJA[1] is TextButton, true);
      expect(widgetsJA[2] is Text, true);

      final widgetsEN = splitTranslationsWithMultipleStyles(
          'I agree to the ArDrive terms of service and privacy policy',
          defaultFactory,
          {'ArDrive terms of service and privacy policy': anchorFactory});
      expect(widgetsEN[0] is Text, true);
      expect(widgetsEN[1] is TextButton, true);
    });
  });
}
