import 'package:ardrive/drives_list/presentation/drive_scope_rail.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A nav row's hover and press are drawn in the shape the selected row has:
/// the row's own inset rounded pill, not a fill on the padding round it that
/// ran edge to edge with square corners.
void main() {
  Future<void> pump(WidgetTester tester, {bool current = false}) =>
      tester.pumpWidget(
        ArDriveApp(
          builder: (context) => MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 240,
                child: DriveNavRow(
                  icon: Icons.home_outlined,
                  label: 'Row',
                  isCurrent: current,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

  Finder pillFinder() => find.byWidgetPredicate(
      (w) => w is Container && w.constraints?.minHeight == 40);

  BoxDecoration? pill(WidgetTester tester) =>
      tester.widget<Container>(pillFinder()).decoration as BoxDecoration?;

  testWidgets('hover draws the pill, inset like the selected row',
      (tester) async {
    await pump(tester);
    expect(pill(tester), isNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Row')));
    await tester.pump();

    final hovered = pill(tester)!;
    expect(hovered.color, isNotNull);
    expect(hovered.borderRadius, BorderRadius.circular(ArDriveRadius.sm));

    final rowLeft = tester.getTopLeft(find.byType(DriveNavRow)).dx;
    final pillLeft = tester.getTopLeft(pillFinder()).dx;
    expect(pillLeft - rowLeft, greaterThan(0), reason: 'inset, not full bleed');
  });

  testWidgets('the selected row has the same shape and place', (tester) async {
    await pump(tester, current: true);
    expect(pill(tester)!.borderRadius, BorderRadius.circular(ArDriveRadius.sm));
  });
}
