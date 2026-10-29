import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Fruit { apple, banana, cherry }

void main() {
  group('ArDriveSelectField', () {
    late _Fruit? value;
    late bool enabled;

    Future<void> pumpField(
      WidgetTester tester, {
      _Fruit? initial,
      bool isEnabled = true,
      String? errorText,
    }) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      value = initial;
      enabled = isEnabled;

      await tester.pumpWidget(
        ArDriveApp(
          builder: (context) => MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(40),
                child: StatefulBuilder(
                  builder: (context, setState) => Column(
                    children: [
                      const ArDriveTextFieldNew(
                        key: ValueKey('text'),
                        label: 'Name',
                      ),
                      SizedBox(
                        width: 320,
                        child: ArDriveSelectField<_Fruit>(
                          key: const ValueKey('select'),
                          label: 'Fruit',
                          hintText: 'Pick a fruit',
                          errorText: errorText,
                          debugLabel: 'fruit',
                          value: value,
                          choices: [
                            for (final fruit in _Fruit.values)
                              ArDriveChoice(
                                key: ValueKey('fruit-${fruit.name}'),
                                value: fruit,
                                label: fruit.name,
                              ),
                          ],
                          onChanged: enabled
                              ? (fruit) => setState(() => value = fruit)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder face() => find.descendant(
          of: find.byKey(const ValueKey('select')),
          matching: find.byType(ArDriveChoiceButton),
        );
    Finder item(_Fruit fruit) => find.byKey(ValueKey('fruit-${fruit.name}'));

    testWidgets('is as tall as a text field', (tester) async {
      await pumpField(tester);

      final textField = find.descendant(
        of: find.byKey(const ValueKey('text')),
        matching: find.byType(TextFormField),
      );
      expect(tester.getSize(face()).height, tester.getSize(textField).height);
    });

    testWidgets('shows the hint, then the chosen value', (tester) async {
      await pumpField(tester);
      expect(find.text('Pick a fruit'), findsOneWidget);

      await tester.tap(face());
      await tester.pumpAndSettle();
      await tester.tap(item(_Fruit.banana));
      await tester.pumpAndSettle();

      expect(value, _Fruit.banana);
      expect(item(_Fruit.banana), findsNothing, reason: 'the menu closed');
      expect(find.text('banana'), findsOneWidget);
    });

    testWidgets('opens under the field, at least as wide, ticking the value',
        (tester) async {
      await pumpField(tester, initial: _Fruit.cherry);

      await tester.tap(face());
      await tester.pumpAndSettle();

      final field = tester.getRect(face());
      final first = tester.getRect(item(_Fruit.apple));
      expect(first.top, greaterThan(field.bottom));
      expect(first.left, closeTo(field.left, 1));
      expect(first.width, greaterThanOrEqualTo(field.width));

      ArDriveChoiceItem row(_Fruit fruit) =>
          tester.widget<ArDriveChoiceItem>(item(fruit));
      expect(row(_Fruit.cherry).selected, isTrue);
      expect(row(_Fruit.apple).selected, isFalse);
    });

    testWidgets('a pointer-opened menu takes no focus', (tester) async {
      await pumpField(tester);

      await tester.tap(face());
      await tester.pumpAndSettle();

      expect(item(_Fruit.apple), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel ?? '',
        isNot(startsWith('fruit')),
      );
    });

    testWidgets('is worked from the keyboard', (tester) async {
      await pumpField(tester, initial: _Fruit.apple);

      final fieldNode = Focus.of(tester.element(find.descendant(
        of: face(),
        matching: find.byType(GestureDetector),
      )));
      fieldNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'fruit apple',
        reason: 'opened from the keyboard, it focuses the current value',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(value, _Fruit.cherry);
      expect(item(_Fruit.cherry), findsNothing);
      expect(fieldNode.hasFocus, isTrue, reason: 'focus is back on the field');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(item(_Fruit.apple), findsOneWidget, reason: 'Down opens it');
    });

    testWidgets('Escape and Tab close it', (tester) async {
      await pumpField(tester);

      await tester.tap(face());
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(item(_Fruit.apple), findsNothing);

      Focus.of(tester.element(find.descendant(
        of: face(),
        matching: find.byType(GestureDetector),
      ))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(item(_Fruit.apple), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(item(_Fruit.apple), findsNothing);
      expect(value, isNull);
    });

    testWidgets('does nothing while disabled', (tester) async {
      await pumpField(tester, isEnabled: false);

      await tester.tap(face());
      await tester.pumpAndSettle();

      expect(item(_Fruit.apple), findsNothing);
    });

    testWidgets('shows an error under the field', (tester) async {
      await pumpField(tester, errorText: 'Pick one');

      expect(find.text('Pick one'), findsOneWidget);
    });

    testWidgets('names itself and its value for a screen reader',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpField(tester, initial: _Fruit.banana);

      expect(
        tester.getSemantics(face()),
        containsSemantics(label: 'Fruit', value: 'banana', isButton: true),
      );

      await tester.tap(face());
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(item(_Fruit.banana)),
        containsSemantics(label: 'banana', isButton: true, isSelected: true),
      );
      semantics.dispose();
    });
  });
}
