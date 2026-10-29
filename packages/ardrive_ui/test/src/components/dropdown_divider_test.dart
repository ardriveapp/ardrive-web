import 'dart:ui';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A menu's groups are split by [ArDriveDropdownItem.divider]: a line that
/// is not an item. It takes no tap, isn't announced, and the menu is sized
/// for its own height, not an item's.
void main() {
  late List<String> tapped;

  Future<void> openMenu(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tapped = [];

    ArDriveDropdownItem item(String name) => ArDriveDropdownItem(
          onClick: () => tapped.add(name),
          content: SizedBox(height: 48, child: Text(name)),
        );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ArDriveDropdown(
                height: 48,
                items: [
                  item('Share'),
                  const ArDriveDropdownItem.divider(),
                  item('Download'),
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
  }

  testWidgets('sits between the groups as a 1 px line', (tester) async {
    await openMenu(tester);

    final share = tester.getRect(find.text('Share'));
    final download = tester.getRect(find.text('Download'));
    expect(download.top - share.bottom, ArDriveDropdownItem.dividerHeight,
        reason: 'the line and its space, not another item');
  });

  testWidgets('is neither a button nor a target', (tester) async {
    final semantics = tester.ensureSemantics();
    await openMenu(tester);

    expect(
      find.bySemanticsLabel(RegExp('Share|Download')),
      findsNWidgets(2),
    );
    // Two buttons, not three.
    final buttons = tester.semantics
        .simulatedAccessibilityTraversal()
        .where((node) => node.hasFlag(SemanticsFlag.isButton));
    expect(buttons, hasLength(2));

    final share = tester.getRect(find.text('Share'));
    await tester.tapAt(Offset(share.center.dx, share.bottom + 4));
    expect(tapped, isEmpty);
    semantics.dispose();
  });

  testWidgets('the menu is sized for it', (tester) async {
    await openMenu(tester);

    final card = tester.getRect(find.byType(ArDriveCard).first);
    expect(card.height, 2 * 48 + ArDriveDropdownItem.dividerHeight);
  });
}
