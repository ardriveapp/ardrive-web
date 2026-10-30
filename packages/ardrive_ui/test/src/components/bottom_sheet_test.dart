import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openSheet(WidgetTester tester, WidgetBuilder builder) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showArDriveBottomSheet(context, builder: builder),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows its title, content and the dialog actions',
      (tester) async {
    var saved = false;
    await openSheet(
      tester,
      (context) => ArDriveBottomSheet(
        title: 'Playback speed',
        content: const Text('1x'),
        actions: [
          ModalAction(action: () => Navigator.pop(context), title: 'Cancel'),
          ModalAction(action: () => saved = true, title: 'Save'),
        ],
      ),
    );

    expect(find.text('Playback speed'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
    expect(find.byType(ArDriveModalActions), findsOneWidget,
        reason: 'the same action row as a dialog');

    await tester.tap(find.text('Save'));
    expect(saved, isTrue);

    final sheet = tester.getRect(find.byType(ArDriveBottomSheet));
    expect(sheet.bottom, 844, reason: 'it sits on the bottom of the screen');
  });

  testWidgets('tall content scrolls inside 85% of the screen', (tester) async {
    await openSheet(
      tester,
      (context) => ArDriveBottomSheet(
        title: 'Long',
        content: Column(
          children: [
            for (var i = 0; i < 60; i++)
              SizedBox(height: 40, child: Text('$i')),
          ],
        ),
        actions: [ModalAction(action: () {}, title: 'Done')],
      ),
    );

    expect(tester.getSize(find.byType(ArDriveBottomSheet)).height,
        lessThanOrEqualTo(844 * 0.85));
    expect(find.text('Done'), findsOneWidget,
        reason: 'the actions stay in view');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sheet that fills its height gives a list the room to scroll',
      (tester) async {
    await openSheet(
      tester,
      (context) => ArDriveBottomSheet(
        title: 'Search',
        fillsHeight: true,
        content: ListView.builder(
          itemCount: 100,
          itemBuilder: (_, i) => SizedBox(height: 40, child: Text('Row $i')),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ArDriveBottomSheet)).height,
        moreOrLessEquals(844 * 0.85, epsilon: 1));
    expect(find.text('Row 0'), findsOneWidget);
    expect(find.text('Row 99'), findsNothing);
  });

  testWidgets('a titled sheet has a named close button that closes it',
      (tester) async {
    await openSheet(
      tester,
      (context) => const ArDriveBottomSheet(
        title: 'Search',
        closeLabel: 'Close',
        content: Text('results'),
      ),
    );
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    expect(find.bySemanticsLabel('Search'), findsOneWidget,
        reason: 'the title keeps its own name');
    semantics.dispose();

    await tester.tap(find.byWidgetPredicate(
        (w) => w is ArDriveIcon && w.icon == ArDriveIconsData.x));
    await tester.pumpAndSettle();
    expect(find.byType(ArDriveBottomSheet), findsNothing);
  });

  testWidgets('a sheet that must not be left has no close button',
      (tester) async {
    await openSheet(
      tester,
      (context) => const ArDriveBottomSheet(
        title: 'Saving the name',
        hasCloseButton: false,
        content: Text('working'),
      ),
    );
    expect(
        find.byWidgetPredicate(
            (w) => w is ArDriveIcon && w.icon == ArDriveIconsData.x),
        findsNothing);
  });

  testWidgets('the sheet dims the page with the standard scrim',
      (tester) async {
    await openSheet(
        tester,
        (context) => const ArDriveBottomSheet(
              content: Text('menu'),
            ));
    final barrier =
        tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).last;
    expect(barrier.color, ArDriveColorTokens.darkMode().scrim);
  });
}
