import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {double width = 400}) => ArDriveApp(
      builder: (context) => MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: width, child: child)),
        ),
      ),
    );

void main() {
  testWidgets('draws every label and reports the tapped segment',
      (tester) async {
    final chosen = <String>[];

    await tester.pumpWidget(_app(ArDriveSegmentedControl<String>(
      selected: 'storage',
      onSelected: chosen.add,
      segments: const [
        ArDriveSegment(value: 'storage', label: 'Storage'),
        ArDriveSegment(value: 'usd', label: 'USD'),
      ],
    )));

    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('USD'), findsOneWidget);

    await tester.tap(find.text('USD'));
    expect(chosen, ['usd']);
  });

  testWidgets('is a regular button high', (tester) async {
    await tester.pumpWidget(_app(ArDriveSegmentedControl<int>(
      selected: 1,
      onSelected: (_) {},
      segments: const [
        ArDriveSegment(value: 1, label: 'One'),
        ArDriveSegment(value: 2, label: 'Two'),
      ],
    )));

    expect(
      tester.getSize(find.byType(ArDriveSegmentedControl<int>)).height,
      ArDriveButtonSize.regular.height,
    );
  });

  testWidgets('tells a screen reader which segment is chosen', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_app(ArDriveSegmentedControl<int>(
      selected: 2,
      onSelected: (_) {},
      segments: const [
        ArDriveSegment(value: 1, label: r'$10'),
        ArDriveSegment(value: 2, label: r'$25'),
      ],
    )));

    expect(
      tester.getSemantics(find.text(r'$25')),
      matchesSemantics(
        isButton: true,
        isSelected: true,
        isFocusable: true,
        hasTapAction: true,
        label: r'$25',
      ),
    );
    expect(
      tester.getSemantics(find.text(r'$10')),
      matchesSemantics(
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        label: r'$10',
      ),
    );
    handle.dispose();
  });

  testWidgets('chooses nothing when no value matches', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_app(ArDriveSegmentedControl<int>(
      selected: null,
      onSelected: (_) {},
      segments: const [
        ArDriveSegment(value: 1, label: 'One'),
        ArDriveSegment(value: 2, label: 'Two'),
      ],
    )));

    for (final label in ['One', 'Two']) {
      expect(
        tester.getSemantics(find.text(label)),
        matchesSemantics(
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          label: label,
        ),
      );
    }
    handle.dispose();
  });

  testWidgets('with expand, shares the width equally', (tester) async {
    await tester.pumpWidget(_app(
      ArDriveSegmentedControl<int>(
        expand: true,
        selected: 1,
        onSelected: (_) {},
        segments: const [
          ArDriveSegment(value: 1, label: r'$10'),
          ArDriveSegment(value: 2, label: r'$25'),
          ArDriveSegment(value: 3, label: r'$100'),
        ],
      ),
      width: 360,
    ));

    final control = tester.getSize(find.byType(ArDriveSegmentedControl<int>));
    expect(control.width, 360);

    final widths = [r'$10', r'$25', r'$100']
        .map((label) => tester
            .getSize(find.ancestor(
              of: find.text(label),
              matching: find.byType(AnimatedContainer),
            ))
            .width)
        .toList();
    expect(widths[0], closeTo(widths[1], 0.01));
    expect(widths[1], closeTo(widths[2], 0.01));
  });

  testWidgets('without expand, hugs its labels', (tester) async {
    await tester.pumpWidget(_app(Align(
      alignment: Alignment.centerLeft,
      child: ArDriveSegmentedControl<int>(
        selected: 1,
        onSelected: (_) {},
        segments: const [
          ArDriveSegment(value: 1, label: 'Storage'),
          ArDriveSegment(value: 2, label: 'USD'),
        ],
      ),
    )));

    expect(
      tester.getSize(find.byType(ArDriveSegmentedControl<int>)).width,
      lessThan(400),
    );
  });

  testWidgets('a wrapped segment takes its taps from the wrapper',
      (tester) async {
    final chosen = <int>[];
    var opened = 0;

    await tester.pumpWidget(_app(ArDriveSegmentedControl<int>(
      selected: 1,
      onSelected: chosen.add,
      segments: [
        const ArDriveSegment(value: 1, label: 'Card'),
        ArDriveSegment(
          value: 2,
          label: 'Crypto',
          trailingIcon: Icons.keyboard_arrow_down,
          wrap: (context, segment) => GestureDetector(
            key: const Key('menu'),
            onTap: () => opened++,
            child: segment,
          ),
        ),
      ],
    )));

    expect(find.byKey(const Key('menu')), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

    await tester.tap(find.text('Crypto'));
    expect(opened, 1);
    expect(chosen, isEmpty);
  });

  testWidgets('Enter on a focused segment chooses it', (tester) async {
    final chosen = <int>[];

    await tester.pumpWidget(_app(ArDriveSegmentedControl<int>(
      selected: 1,
      onSelected: chosen.add,
      segments: const [
        ArDriveSegment(value: 1, label: 'One'),
        ArDriveSegment(value: 2, label: 'Two'),
      ],
    )));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(chosen, [2]);
  });
}
