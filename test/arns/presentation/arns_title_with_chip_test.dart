import 'package:ardrive/arns/presentation/item/arns_item_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, String title) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: ArNSTitleWithChip(
                  title: Text(title, key: const Key('title')),
                  chip: const SizedBox(
                    key: Key('chip'),
                    width: 200,
                    height: 16,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  // A file row on a 390 px phone: the chip kept its 200 px and the file
  // name was laid out five letters to a line.
  testWidgets('a long title keeps the width and the chip goes under it',
      (tester) async {
    await pump(tester, 'Michelangelo_-_Creation_of_Adam_(cropped).jpg');

    expect(
        tester.getSize(find.byKey(const Key('title'))).width, greaterThan(200));
    expect(
        tester.getTopLeft(find.byKey(const Key('chip'))).dy,
        greaterThanOrEqualTo(
            tester.getBottomLeft(find.byKey(const Key('title'))).dy));
  });

  testWidgets('a short title keeps the chip beside it', (tester) async {
    await pump(tester, 'a.txt');

    final title = tester.getRect(find.byKey(const Key('title')));
    final chip = tester.getRect(find.byKey(const Key('chip')));
    expect(chip.left, greaterThanOrEqualTo(title.right));
    expect(chip.top, lessThan(title.bottom));
  });
}
