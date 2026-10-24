import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Counter {
  int count = 0;

  void add() => ++count;
}

void main() {
  testWidgets('Should click and update the counter class using in all styles',
      (tester) async {
    _Counter counterPrimary = _Counter();
    _Counter counterSecondary = _Counter();
    _Counter counterTertiary = _Counter();

    final buttonPrimary = ArDriveButton(
      style: ArDriveButtonStyle.primary,
      text: 'Add',
      onPressed: () {
        return counterPrimary.add();
      },
    );
    final buttonSecondary = ArDriveButton(
      style: ArDriveButtonStyle.secondary,
      text: 'Add',
      onPressed: () {
        return counterSecondary.add();
      },
    );
    final buttonTertiary = ArDriveButton(
      style: ArDriveButtonStyle.tertiary,
      text: 'Add',
      onPressed: () {
        return counterTertiary.add();
      },
    );
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: buttonPrimary,
        ),
      ),
    );

    await tester.tap(find.byType(ArDriveButton));

    expect(counterPrimary.count, 1);

    /// Secondary
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: buttonSecondary,
        ),
      ),
    );

    await tester.tap(find.byType(ArDriveButton));

    expect(counterSecondary.count, 1);

    /// Tertiary
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: buttonTertiary,
        ),
      ),
    );

    await tester.tap(find.byType(ArDriveButton));

    expect(counterTertiary.count, 1);
  });

  testWidgets('Test if button renders', (tester) async {
    final button = ArDriveButton(
      text: 'Add',
      onPressed: () {},
    );
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: button,
      ),
    ));

    expect(find.byWidget(button), findsOneWidget);
  });
  testWidgets('Test if the text is used correctly on primary', (tester) async {
    final button = ArDriveButton(
      text: 'Text',
      onPressed: () {},
    );
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: button,
      ),
    ));

    expect(find.text('Text'), findsOneWidget);
  });

  testWidgets('Test if the text is used correctly on Secondary',
      (tester) async {
    final button = ArDriveButton(
      style: ArDriveButtonStyle.secondary,
      text: 'Text',
      onPressed: () {},
    );
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: button,
      ),
    ));

    expect(find.text('Text'), findsOneWidget);
  });

  /// A caller that only wants a different size or weight must not lose the
  /// button's colour. `TextStyle.color` left null falls through to the
  /// button's `foregroundColor`, which for the secondary style is the surface
  /// colour - text the same colour as the panel behind it, which in dark mode
  /// reads as absent. 48 call sites across the app pass a style this way.
  testWidgets('a partial fontStyle keeps the secondary button text colour',
      (tester) async {
    late Color expectedColor;

    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: Builder(builder: (context) {
          expectedColor =
              ArDriveTheme.of(context).themeData.colors.themeFgDefault;
          return ArDriveButton(
            style: ArDriveButtonStyle.secondary,
            text: 'Text',
            // Size and weight only - no colour, as the snapshots tab does.
            fontStyle: const TextStyle(fontSize: 12),
            onPressed: () {},
          );
        }),
      ),
    ));

    final text = tester.widget<Text>(find.text('Text'));

    expect(text.style?.fontSize, 12,
        reason: "the caller's own values still win");
    expect(text.style?.color, expectedColor,
        reason: 'the colour it did not set must fall back, not vanish');
  });

  testWidgets('Test if the text is used correctly on Tertiary', (tester) async {
    final button = ArDriveButton(
      style: ArDriveButtonStyle.tertiary,
      text: 'Text',
      onPressed: () {},
    );
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: button,
      ),
    ));

    expect(find.text('Text'), findsOneWidget);
  });

  testWidgets('Test if the text is used correctly on Tertiary', (tester) async {
    final button = ArDriveButton(
      style: ArDriveButtonStyle.tertiary,
      text: 'Text',
      onPressed: () {},
    );

    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: button,
      ),
    ));

    expect(find.text('Text'), findsOneWidget);
  });

  testWidgets('Test if ArDriveButton returns ElevatedButton when primary',
      (tester) async {
    final button = ArDriveButton(
      text: 'Text',
      onPressed: () {},
    );

    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: button,
      ),
    ));

    expect(find.bySubtype<ElevatedButton>(), findsOneWidget);
  });
  testWidgets('Test if ArDriveButton returns OutlinedButton when tertiary',
      (tester) async {
    final button = ArDriveButton(
      style: ArDriveButtonStyle.secondary,
      text: 'Text',
      onPressed: () {},
    );

    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: button,
      ),
    ));

    expect(find.bySubtype<OutlinedButton>(), findsOneWidget);
  });
  testWidgets('Test if ArDriveButton returns ArDriveTextButton when tertiary',
      (tester) async {
    final button = ArDriveButton(
      style: ArDriveButtonStyle.tertiary,
      text: 'Text',
      onPressed: () {},
    );

    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: button,
      ),
    ));

    expect(find.bySubtype<ArDriveTextButton>(), findsOneWidget);
  });

  /// The login page's buttons show an icon on hover. It used to slide the
  /// label out to make room, so the button was blank under the pointer and
  /// stayed blank behind the dialog the click opened.
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
}
