import 'package:ardrive_ui/ardrive_ui.dart';
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
}
