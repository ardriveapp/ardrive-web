import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A menu fades and settles in over about 150 ms and out over about 110 ms,
/// and stays in the overlay until it has gone: it used to appear and vanish
/// in a single frame.
void main() {
  final opens = <bool>[];

  Future<void> pump(WidgetTester tester, {bool reduced = false}) async {
    opens.clear();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ArDriveDropdown(
                onOpenChanged: opens.add,
                items: [
                  ArDriveDropdownItem(
                    onClick: () {},
                    content: const SizedBox(height: 48, child: Text('Pick')),
                  ),
                ],
                child:
                    const SizedBox(width: 24, height: 24, child: Text('menu')),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double opacityOfMenu(WidgetTester tester) {
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
              of: find.byType(ArDriveCard),
              matching: find.byType(FadeTransition))
          .first,
    );
    return fade.opacity.value;
  }

  testWidgets('fades in rather than appearing at once', (tester) async {
    await pump(tester);
    await tester.tap(find.text('menu'));
    await tester.pump(); // the entry is inserted after the frame
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('Pick'), findsOneWidget);
    expect(opacityOfMenu(tester), lessThan(0.5));

    await tester.pump(const Duration(milliseconds: 80));
    final mid = opacityOfMenu(tester);
    expect(mid, greaterThan(0.3));
    expect(mid, lessThan(1));

    await tester.pump(const Duration(milliseconds: 100));
    expect(opacityOfMenu(tester), 1);
  });

  testWidgets('stays until it has faded out, then goes', (tester) async {
    await pump(tester);
    await tester.tap(find.text('menu'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pick'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('Pick'), findsOneWidget, reason: 'still fading out');
    expect(opacityOfMenu(tester), lessThan(1));

    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Pick'), findsNothing);
    expect(opens, [true, false]);
  });

  testWidgets('a menu that is closing takes no clicks', (tester) async {
    await pump(tester);
    await tester.tap(find.text('menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      tester
          .widget<IgnorePointer>(find
              .ancestor(
                  of: find.byType(ArDriveCard),
                  matching: find.byType(IgnorePointer))
              .last)
          .ignoring,
      isTrue,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('opens again while still closing', (tester) async {
    await pump(tester);
    await tester.tap(find.text('menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.text('menu'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Pick'), findsOneWidget);
    expect(opacityOfMenu(tester), 1);
  });

  testWidgets('with reduced motion it is there and gone at once',
      (tester) async {
    await pump(tester, reduced: true);
    await tester.tap(find.text('menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Pick'), findsOneWidget);
    expect(opacityOfMenu(tester), 1);

    await tester.tap(find.text('Pick'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Pick'), findsNothing);
  });

  testWidgets('Enter on the item during the fade-out does not open it again',
      (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Pick'), findsOneWidget, reason: 'open');

    // Picks and closes, and again at once: the item is still focused.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Pick'), findsNothing, reason: 'stays closed');
    expect(opens, [true, false]);
  });
}
