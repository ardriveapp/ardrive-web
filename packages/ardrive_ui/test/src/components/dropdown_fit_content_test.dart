import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A menu told to fit its content is as tall as what is in it, up to its
/// height, rather than exactly that height: a header that is one line long
/// takes one line, not a fixed block with most of it blank.
void main() {
  const headerKey = Key('header');

  Future<double> menuHeight(WidgetTester tester, {required bool fit}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ArDriveDropdown(
                maxHeight: 400,
                fitContent: fit,
                header: const SizedBox(key: headerKey, height: 40, width: 200),
                items: [
                  ArDriveDropdownItem(
                    onClick: () {},
                    content: const SizedBox(height: 48, child: Text('Dismiss')),
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
    await tester.tap(find.text('menu'));
    await tester.pumpAndSettle();

    return tester.getSize(find.byType(ArDriveCard)).height;
  }

  testWidgets('fits what is in it when asked to', (tester) async {
    final height = await menuHeight(tester, fit: true);

    expect(height, lessThan(400));
    expect(height, greaterThanOrEqualTo(40 + 48));
  });

  testWidgets('and is the height it is given otherwise', (tester) async {
    final height = await menuHeight(tester, fit: false);

    expect(height, 400);
  });
}
