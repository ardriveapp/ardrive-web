import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// An item without an onClick is not an action: a line to read, such as the
/// version at the foot of the sign-in settings menu. It used to be wrapped
/// like every other item, so it showed a pointer and a click on it closed
/// the menu while doing nothing.
void main() {
  var clicked = 0;

  Widget menu({List<ArDriveSubmenuItem>? extra}) => ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ArDriveSubmenu(
                menuChildren: [
                  ArDriveSubmenuItem(
                    widget: const SizedBox(
                      width: 200,
                      height: 40,
                      child: Text('Set gateway'),
                    ),
                    onClick: () => clicked++,
                  ),
                  ArDriveSubmenuItem(
                    widget: const SizedBox(
                      width: 200,
                      height: 40,
                      child: Text('Version 2.90.0'),
                    ),
                  ),
                  ...?extra,
                ],
                child:
                    const SizedBox(width: 40, height: 40, child: Text('cog')),
              ),
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester tester,
      {List<ArDriveSubmenuItem>? extra}) async {
    clicked = 0;
    await tester.pumpWidget(menu(extra: extra));
    await tester.tap(find.text('cog'));
    await tester.pumpAndSettle();
    expect(find.text('Version 2.90.0'), findsOneWidget);
  }

  testWidgets('a tap on it leaves the menu open', (tester) async {
    await open(tester);

    await tester.tap(find.text('Version 2.90.0'));
    await tester.pumpAndSettle();

    expect(find.text('Version 2.90.0'), findsOneWidget);
    expect(find.text('Set gateway'), findsOneWidget);
  });

  testWidgets('it shows the basic cursor, and an action the pointer',
      (tester) async {
    await open(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);

    await mouse.moveTo(tester.getCenter(find.text('Version 2.90.0')));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.basic,
    );

    await mouse.moveTo(tester.getCenter(find.text('Set gateway')));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
  });

  testWidgets('it is not a button to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);

    expect(
      tester.getSemantics(find.text('Version 2.90.0')),
      isNot(containsSemantics(isButton: true)),
    );
    expect(
      tester.getSemantics(find.text('Set gateway')),
      containsSemantics(isButton: true, hasTapAction: true),
    );
    handle.dispose();
  });

  testWidgets('an action still runs and closes the menu', (tester) async {
    await open(tester);

    await tester.tap(find.text('Set gateway'));
    await tester.pumpAndSettle();

    expect(clicked, 1);
    expect(find.text('Version 2.90.0'), findsNothing);
  });

  testWidgets('outside a menu there is none to close', (tester) async {
    VoidCallback? close = () {};
    await tester.pumpWidget(Builder(builder: (context) {
      close = ArDriveSubmenu.maybeCloseOf(context);
      return const SizedBox();
    }));
    expect(close, isNull);
  });

  testWidgets('a link inside it closes the menu with maybeCloseOf',
      (tester) async {
    await open(tester, extra: [
      ArDriveSubmenuItem(
        widget: Builder(
          builder: (context) => GestureDetector(
            onTap: () => ArDriveSubmenu.maybeCloseOf(context)?.call(),
            child: const Text("What's new"),
          ),
        ),
      ),
    ]);

    await tester.tap(find.text("What's new"));
    await tester.pumpAndSettle();

    expect(find.text('Version 2.90.0'), findsNothing);
  });
}
