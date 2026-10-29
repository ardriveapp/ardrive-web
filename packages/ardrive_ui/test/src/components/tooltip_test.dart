import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tooltip shows what it names and stays out of the way of clicks.
void main() {
  late List<String> tapped;

  setUp(() => tapped = []);

  /// Two rows, one under the other, each with its name in a tooltip, as in
  /// the file table. A tooltip is drawn under what it names, so the first
  /// row's lies over the top of the second.
  Future<void> pumpRows(WidgetTester tester) async {
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                for (final name in ['first.txt', 'second.txt'])
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tapped.add(name),
                    child: SizedBox(
                      height: 44,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ArDriveTooltip(
                          message: name,
                          child: Text(name),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    return gesture;
  }

  /// Where the shown tooltip [message] is drawn.
  Rect bubble(WidgetTester tester, String message) => tester.getRect(
        find
            .ancestor(
              of: find.text(message).last,
              matching: find.byType(DecoratedBox),
            )
            .first,
      );

  testWidgets('shows on hover, under what it names, and goes on leaving',
      (tester) async {
    await pumpRows(tester);
    final pointer = await mouse(tester);

    expect(find.text('first.txt'), findsOneWidget);

    await pointer.moveTo(tester.getCenter(find.text('first.txt')));
    await tester.pumpAndSettle();

    expect(find.text('first.txt'), findsNWidgets(2));
    expect(
      bubble(tester, 'first.txt').top,
      greaterThan(tester.getCenter(find.text('first.txt').first).dy),
    );

    await pointer.moveTo(const Offset(700, 500));
    await tester.pumpAndSettle();

    expect(find.text('first.txt'), findsOneWidget);
  });

  // The bug: the first row's tooltip lies over the second row, and a mouse
  // moving down onto the second row went over it. The tooltip took the
  // click, so the second row did not get it: on a publication, where a click
  // opens a row, the first click did nothing (issue #2367).
  testWidgets('a click on what lies under it lands there, not on the tooltip',
      (tester) async {
    await pumpRows(tester);
    final pointer = await mouse(tester);

    await pointer.moveTo(tester.getCenter(find.text('first.txt')));
    await tester.pumpAndSettle();

    final over = bubble(tester, 'first.txt');
    final target = over.center;
    expect(
      tester.getRect(find.byType(GestureDetector).last).contains(target),
      isTrue,
      reason: 'the tooltip must lie over the second row',
    );

    await pointer.moveTo(target);
    await tester.pump();
    await pointer.down(target);
    await pointer.up();
    await tester.pumpAndSettle();

    expect(tapped, ['second.txt']);
  });

  testWidgets('a click puts it away', (tester) async {
    await pumpRows(tester);
    final pointer = await mouse(tester);

    final name = tester.getCenter(find.text('first.txt'));
    await pointer.moveTo(name);
    await tester.pumpAndSettle();
    expect(find.text('first.txt'), findsNWidgets(2));

    await pointer.down(name);
    await pointer.up();
    await tester.pumpAndSettle();

    expect(tapped, ['first.txt']);
    expect(find.text('first.txt'), findsOneWidget);
  });

  testWidgets('a long press shows it on a touch screen, for a while',
      (tester) async {
    await pumpRows(tester);

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('first.txt')));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('first.txt'), findsNWidgets(2));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('first.txt'), findsNWidgets(2));

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('first.txt'), findsOneWidget);
  });

  testWidgets('tells a screen reader what it names', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpRows(tester);

    expect(
      tester.getSemantics(find.text('first.txt')),
      matchesSemantics(
        label: 'first.txt',
        tooltip: 'first.txt',
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('with no message it is only what it wraps', (tester) async {
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: const MaterialApp(
          home: ArDriveTooltip(message: '', child: Text('plain')),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(ArDriveTooltip),
        matching: find.byType(MouseRegion),
      ),
      findsNothing,
    );
  });

  // Material's own tooltip is kept around the child with its label switched
  // off, and that switch must not reach the tooltips inside the child: the
  // profile chip's truncated name sits in a tooltip inside another.
  group('a tooltip inside one still shows', () {
    Future<void> pumpNested(WidgetTester tester, Widget inner) =>
        tester.pumpWidget(
          ArDriveTheme(
            themeData: lightTheme(),
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: ArDriveTooltip(message: 'outer', child: inner),
                ),
              ),
            ),
          ),
        );

    testWidgets("Material's, on hover", (tester) async {
      await pumpNested(
        tester,
        const Tooltip(message: 'inner', child: Text('name')),
      );
      final pointer = await mouse(tester);

      await pointer.moveTo(tester.getCenter(find.text('name')));
      await tester.pumpAndSettle();

      expect(find.text('inner'), findsOneWidget);
    });

    testWidgets("an icon button's, on a long press", (tester) async {
      await pumpNested(
        tester,
        IconButton(
          tooltip: 'inner',
          onPressed: () {},
          icon: const Icon(Icons.close),
        ),
      );

      await tester.longPress(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('inner'), findsOneWidget);
    });

    testWidgets('our own, on hover', (tester) async {
      await pumpNested(
        tester,
        const ArDriveTooltip(message: 'inner', child: Text('name')),
      );
      final pointer = await mouse(tester);

      await pointer.moveTo(tester.getCenter(find.text('name')));
      await tester.pumpAndSettle();

      expect(find.text('inner'), findsOneWidget);
    });
  });
}
