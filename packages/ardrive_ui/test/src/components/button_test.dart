import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ArDriveButtonNew keeps its label while hovered', (tester) async {
    const iconKey = Key('hover-icon');

    // A desktop width: phones have no hover, and the button draws no icon.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: ArDriveButtonNew(
                text: 'Import wallet',
                typography: ArDriveTypographyNew.of(context),
                maxWidth: 380,
                hoverIcon: const Icon(Icons.wallet, key: iconKey),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final button = tester.getRect(find.byType(ArDriveButtonNew));
    expect(find.byKey(iconKey), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(button.center);
    await tester.pumpAndSettle();

    expect(find.byKey(iconKey), findsOneWidget);

    final label = tester.getRect(find.text('Import wallet'));
    final icon = tester.getRect(find.byKey(iconKey));
    expect(button.contains(label.center), isTrue,
        reason: 'the label is still inside the button');
    expect(icon.right, lessThanOrEqualTo(label.left),
        reason: 'the icon sits beside the label, not over it');
    expect(icon.center.dy, closeTo(label.center.dy, 2));

    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();

    expect(find.byKey(iconKey), findsNothing);
    expect(button.contains(tester.getRect(find.text('Import wallet')).center),
        isTrue);
  });

  /// A button with no width is as wide as its label. A left icon is drawn
  /// over the label's row, so that width has to leave it room.
  testWidgets('ArDriveButtonNew sized to its label keeps a left icon clear',
      (tester) async {
    const iconKey = Key('left-icon');

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: ArDriveButtonNew(
                text: 'Upload',
                typography: ArDriveTypographyNew.of(context),
                icon: const SizedBox.square(dimension: 24, key: iconKey),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final button = tester.getRect(find.byType(ArDriveButtonNew));
    final label = tester.getRect(find.text('Upload'));
    final icon = tester.getRect(find.byKey(iconKey));
    expect(icon.right, lessThanOrEqualTo(label.left),
        reason: 'the icon sits beside the label, not over it');
    expect(button.contains(label.centerRight - const Offset(1, 0)), isTrue,
        reason: 'the whole label is inside the button');
  });

  /// A label-sized button with both icons leaves room for both: the right one
  /// is drawn over the edge of the row, clear of the centred icon and label.
  testWidgets('ArDriveButtonNew sized to its label keeps both icons clear',
      (tester) async {
    const leftKey = Key('left-icon');
    const rightKey = Key('right-icon');

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: ArDriveButtonNew(
                text: 'Upload',
                typography: ArDriveTypographyNew.of(context),
                icon: const SizedBox.square(dimension: 24, key: leftKey),
                rightIcon: const SizedBox.square(dimension: 24, key: rightKey),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final button = tester.getRect(find.byType(ArDriveButtonNew));
    final label = tester.getRect(find.text('Upload'));
    final left = tester.getRect(find.byKey(leftKey));
    final right = tester.getRect(find.byKey(rightKey));
    expect(left.right, lessThanOrEqualTo(label.left));
    expect(label.right, lessThanOrEqualTo(right.left),
        reason: 'the right icon is clear of the label');
    expect(button.contains(right.center), isTrue);
  });

  /// A hover icon joins a left icon; it never takes its place, hovered or not.
  testWidgets('ArDriveButtonNew keeps its icon when it also has a hover icon',
      (tester) async {
    const iconKey = Key('left-icon');
    const hoverKey = Key('hover-icon');

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: ArDriveButtonNew(
                text: 'Import wallet',
                typography: ArDriveTypographyNew.of(context),
                maxWidth: 380,
                icon: const SizedBox.square(dimension: 24, key: iconKey),
                hoverIcon: const Icon(Icons.wallet, key: hoverKey),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(iconKey), findsOneWidget, reason: 'before hover');
    expect(find.byKey(hoverKey), findsNothing);

    final button = tester.getRect(find.byType(ArDriveButtonNew));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(button.center);
    await tester.pumpAndSettle();

    expect(find.byKey(iconKey), findsOneWidget, reason: 'while hovered');
    expect(find.byKey(hoverKey), findsOneWidget);
    expect(tester.getRect(find.byKey(iconKey)).right,
        lessThanOrEqualTo(tester.getRect(find.text('Import wallet')).left));
  });

  /// A full-width button with an icon fills its width like any other, so it
  /// lines up with the column it sits in. Its fill was inset 24 px on each
  /// side, which left a full-width Download 48 px narrower than its card.
  testWidgets('ArDriveButtonNew with an icon fills the width it is given',
      (tester) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: ArDriveButtonNew(
                text: 'Download',
                typography: ArDriveTypographyNew.of(context),
                maxWidth: double.infinity,
                icon: const SizedBox.square(dimension: 20),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final button = tester.getRect(find.byType(ArDriveButtonNew));
    final fill = tester.getRect(find.byType(TextButton));
    expect(button.width, 320);
    expect(fill.left, button.left);
    expect(fill.right, button.right);
  });

  /// Three heights, chosen by where the button sits. Buttons were 30, 36, 40,
  /// 45, 46, 56 and 60 high, so no two screens matched.
  testWidgets('ArDriveButtonNew comes in three heights', (tester) async {
    for (final (size, height) in [
      (ArDriveButtonSize.compact, 36.0),
      (ArDriveButtonSize.regular, 40.0),
      (ArDriveButtonSize.large, 48.0),
    ]) {
      await tester.pumpWidget(
        ArDriveApp(
          builder: (context) => MaterialApp(
            home: Scaffold(
              body: Center(
                child: ArDriveButtonNew(
                  text: 'Save',
                  typography: ArDriveTypographyNew.of(context),
                  size: size,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(ArDriveButtonNew)).height, height,
          reason: '$size');
    }
  });

  testWidgets('ArDriveButtonNew is the regular height by default',
      (tester) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: ArDriveButtonNew(
                text: 'Save',
                typography: ArDriveTypographyNew.of(context),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(ArDriveButtonNew)).height, 40);
  });
}
