import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => ArDriveApp(
      builder: (context) => MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 160, height: 120, child: child)),
        ),
      ),
    );

void main() {
  group('ArDriveGalleryTile', () {
    testWidgets('a screen reader hears the name, then the type, then the state',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(ArDriveGalleryTile(
        name: 'Pier.jpg',
        typeLabel: 'JPEG image',
        selected: true,
        onTap: () {},
      )));
      final node = tester.getSemantics(find.byType(ArDriveGalleryTile));
      expect(node.label, 'Pier.jpg, JPEG image');
      expect(node.hasFlag(SemanticsFlag.isSelected), isTrue);
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      handle.dispose();
    });

    testWidgets('content replaces the photo and keeps the tile\'s behaviour',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(ArDriveGalleryTile(
        name: 'Notes',
        content: const Text('doc'),
        onTap: () => taps++,
      )));
      expect(find.text('doc'), findsOneWidget);
      expect(find.byKey(const ValueKey('gallery-tile-skeleton')), findsNothing);
      await tester.tap(find.text('doc'), kind: PointerDeviceKind.mouse);
      expect(taps, 1);
    });

    testWidgets('a long press is reported', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(wrap(ArDriveGalleryTile(
        name: 'a.jpg',
        onTap: () {},
        onLongPress: () => pressed++,
      )));
      await tester.longPress(find.byType(ArDriveGalleryTile));
      expect(pressed, 1);
    });

    testWidgets('the trailing control shows on hover, selection or request',
        (tester) async {
      const trailing = ValueKey('gallery-tile-trailing');
      Widget tile({bool selected = false, bool keep = false}) =>
          wrap(ArDriveGalleryTile(
            name: 'a.jpg',
            onTap: () {},
            selected: selected,
            keepTrailing: keep,
            trailing: const SizedBox(width: 20, height: 20),
          ));

      await tester.pumpWidget(tile());
      expect(find.byKey(trailing), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(ArDriveGalleryTile)));
      await tester.pump();
      expect(find.byKey(trailing), findsOneWidget);

      await mouse.moveTo(const Offset(2, 2));
      await tester.pump();
      expect(find.byKey(trailing), findsNothing);

      await tester.pumpWidget(tile(selected: true));
      expect(find.byKey(trailing), findsOneWidget);
      await tester.pumpWidget(tile(keep: true));
      expect(find.byKey(trailing), findsOneWidget);
    });
  });

  group('ArDriveDropdownController', () {
    testWidgets('opens the menu from code, once', (tester) async {
      final controller = ArDriveDropdownController();
      await tester.pumpWidget(ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ArDriveDropdown(
                controller: controller,
                items: [
                  ArDriveDropdownItem(
                    onClick: () {},
                    content: const SizedBox(height: 48, child: Text('Open it')),
                  ),
                ],
                child: const SizedBox(width: 24, height: 24),
              ),
            ),
          ),
        ),
      ));
      expect(find.text('Open it'), findsNothing);
      expect(controller.isOpen, isFalse);
      controller.open();
      await tester.pumpAndSettle();
      expect(find.text('Open it'), findsOneWidget);
      expect(controller.isOpen, isTrue);
      // Already open: opening again does not close it.
      controller.open();
      await tester.pumpAndSettle();
      expect(find.text('Open it'), findsOneWidget);
    });
  });
}
