import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A long dialog did not show that it scrolled: no scrollbar until it was
/// scrolled, and nothing at its foot to say there was more. The scroll area
/// shows both while content waits below.
void main() {
  final moreBelow = find.byKey(ArDriveScrollArea.moreBelowKey);

  Widget lines(int count) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < count; i++)
            SizedBox(height: 40, child: Text('Line $i')),
        ],
      );

  Future<void> pumpModal(
    WidgetTester tester, {
    required Size size,
    required int count,
    bool light = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ArDriveApp(
        themeData: light ? lightTheme() : null,
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: ArDriveStandardModalNew(
                title: 'Title',
                scrollableContent: true,
                content: lines(count),
                actions: [
                  ModalAction(action: () {}, title: 'Back'),
                  ModalAction(action: () {}, title: 'Next'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  RawScrollbar scrollbar(WidgetTester tester) =>
      tester.widget<RawScrollbar>(find.byType(RawScrollbar).first);

  for (final (name, size) in [
    ('desktop', const Size(1280, 800)),
    ('phone', const Size(390, 844)),
  ]) {
    testWidgets(
        'a long dialog shows a scrollbar and a divider over its actions, '
        'gone at the bottom ($name)', (tester) async {
      await pumpModal(tester, size: size, count: 60);

      expect(scrollbar(tester).thumbVisibility, isTrue);
      expect(moreBelow, findsOneWidget);
      // The divider sits at the foot of the content, above the actions.
      expect(tester.getBottomLeft(moreBelow).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.text('Next')).dy));

      await tester.drag(find.text('Line 3'), const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(moreBelow, findsNothing, reason: 'nothing more below');

      await tester.drag(find.text('Line 59'), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(moreBelow, findsOneWidget, reason: 'more below again');
    });
  }

  testWidgets('a dialog that fits shows no divider, in either theme',
      (tester) async {
    for (final light in [false, true]) {
      await pumpModal(tester,
          size: const Size(1280, 800), count: 2, light: light);
      expect(moreBelow, findsNothing);
      expect(find.text('Next'), findsOneWidget);
    }
  });

  testWidgets('a long bottom sheet shows it scrolls too', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showArDriveBottomSheet(
                  context,
                  builder: (context) => ArDriveBottomSheet(
                    title: 'Sheet',
                    content: lines(60),
                    actions: [ModalAction(action: () {}, title: 'Done')],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(scrollbar(tester).thumbVisibility, isTrue);
    expect(moreBelow, findsOneWidget);

    await tester.drag(find.text('Line 3'), const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(moreBelow, findsNothing);
  });
}
