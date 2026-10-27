import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A row's menu used to choose up or down from which half of the screen its
/// button was in, measured once when the row was first laid out. A long menu
/// on a row just above the middle opened down and ran off the bottom, and its
/// last items (Hide, More info) could not be reached.
void main() {
  Future<void> openMenuAt(
    WidgetTester tester, {
    required double top,
    required int items,
    Aligned anchor = const Aligned(
      follower: Alignment.topRight,
      target: Alignment.topLeft,
    ),
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: top,
                  right: 40,
                  child: ArDriveDropdown(
                    calculateVerticalAlignment: (opensUp) =>
                        opensUp ? Alignment.bottomRight : Alignment.topRight,
                    height: 48,
                    anchor: anchor,
                    items: [
                      for (var i = 0; i < items; i++)
                        ArDriveDropdownItem(
                          onClick: () {},
                          content: SizedBox(
                            height: 48,
                            child: Text('Item $i'),
                          ),
                        ),
                    ],
                    child: const SizedBox(
                      width: 24,
                      height: 24,
                      child: Text('menu'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('menu'));
    await tester.pumpAndSettle();
  }

  Rect menuRect(WidgetTester tester) =>
      tester.getRect(find.byType(ArDriveCard).first);

  testWidgets('a long menu just above the middle stays on the screen',
      (tester) async {
    await openMenuAt(tester, top: 440, items: 12);

    final rect = menuRect(tester);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(900));
    // Its last item can be reached, by scrolling when the menu is capped.
    await tester.scrollUntilVisible(find.text('Item 11'), 48,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Item 11').hitTestable(), findsOneWidget);
  });

  testWidgets('a short menu near the top still opens down', (tester) async {
    await openMenuAt(tester, top: 100, items: 3);

    final rect = menuRect(tester);
    expect(rect.top, greaterThanOrEqualTo(100));
    expect(rect.bottom, lessThanOrEqualTo(900));
  });

  testWidgets('a menu in the lower half still opens up', (tester) async {
    await openMenuAt(tester, top: 700, items: 3);

    final rect = menuRect(tester);
    expect(rect.bottom, lessThanOrEqualTo(700));
  });

  testWidgets(
      'a fitted menu hanging from its button\'s bottom stays on the screen',
      (tester) async {
    // The Names page and drive actions menus hang from the bottom of a 24px
    // button, 4px below it. Room measured from the button's top let this
    // menu run 28px past the bottom of the screen.
    await openMenuAt(
      tester,
      top: 300,
      items: 14,
      anchor: const Aligned(
        follower: Alignment.topRight,
        target: Alignment.bottomRight,
        offset: Offset(0, 4),
      ),
    );

    final rect = menuRect(tester);
    expect(rect.top, greaterThanOrEqualTo(328));
    expect(rect.bottom, lessThanOrEqualTo(900));
  });

  // Placed again when the window changed, the menu was drawn with its old
  // placement and height until something else rebuilt it.
  testWidgets('an open menu is placed again when the window shrinks',
      (tester) async {
    await openMenuAt(tester, top: 100, items: 14);
    expect(menuRect(tester).bottom, greaterThan(600));

    tester.view.physicalSize = const Size(1440, 600);
    await tester.pumpAndSettle();

    expect(menuRect(tester).bottom, lessThanOrEqualTo(600));
  });
}
