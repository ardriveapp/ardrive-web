import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CheckBox widget and its contents render', (tester) async {
    const checkBox = ArDriveCheckBox(
      title: 'Title',
    );

    await tester.pumpWidget(ArDriveApp(
      builder: (context) => const MaterialApp(
        home: checkBox,
      ),
    ));

    expect(find.byWidget(checkBox), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('CheckBox inits with the correct state checked', (tester) async {
    const checkBoxChecked = ArDriveCheckBox(
      title: 'Title',
      checked: true,
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(
          home: checkBoxChecked,
        ),
      ),
    );

    final state =
        tester.state<ArDriveCheckBoxState>(find.byType(ArDriveCheckBox));

    /// Should be checked because we initialized it with `checked` true
    expect(state.state, CheckBoxState.checked);
  });
  testWidgets('CheckBox inits with the correct state unChecked',
      (tester) async {
    const checkBoxUnChecked = ArDriveCheckBox(
      title: 'Title',
    );

    /// Disabled
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(
          home: checkBoxUnChecked,
        ),
      ),
    );

    /// Check false
    /// Indeterminate
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(
          home: checkBoxUnChecked,
        ),
      ),
    );

    final uncheckedState =
        tester.state<ArDriveCheckBoxState>(find.byWidget(checkBoxUnChecked));

    /// Should be checked because we initialized it without `checked`
    expect(uncheckedState.state, CheckBoxState.normal);
  });
  testWidgets('CheckBox inits with the correct state checked', (tester) async {
    const checkBoxDisabled = ArDriveCheckBox(
      title: 'Title',
      isDisabled: true,
    );

    /// Disabled
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(
          home: checkBoxDisabled,
        ),
      ),
    );

    final disabledState =
        tester.state<ArDriveCheckBoxState>(find.byWidget(checkBoxDisabled));

    /// Should be checked because we initialized it with `disabled` true
    expect(disabledState.state, CheckBoxState.disabled);
  });
  testWidgets('CheckBox inits with the correct state checked', (tester) async {
    const checkBoxIndeterminate = ArDriveCheckBox(
      title: 'Title',
      isIndeterminate: true,
    );

    /// Indeterminate
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(
          home: checkBoxIndeterminate,
        ),
      ),
    );

    final indeterminateState = tester
        .state<ArDriveCheckBoxState>(find.byWidget(checkBoxIndeterminate));

    /// Should be checked because we initialized it with `indeterminate` true
    expect(indeterminateState.state, CheckBoxState.indeterminate);
  });
  testWidgets('CheckBox change state correctly', (tester) async {
    const checkbox = ArDriveCheckBox(
      title: 'Title',
      key: Key('checkbox'),
      useNewIcons: false,
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(
          home: checkbox,
        ),
      ),
    );

    /// Gets the container to tap
    final findCheckBox = find.byType(AnimatedContainer).first;

    final state =
        tester.state<ArDriveCheckBoxState>(find.byType(ArDriveCheckBox));

    /// Should be `normal` because we initialized it without `checked`
    expect(state.state, CheckBoxState.normal);

    await tester.ensureVisible(findCheckBox);
    await tester.pumpAndSettle();
    await tester.tap(findCheckBox);

    /// After tap it should be the normal state
    final stateAfterTap =
        tester.state<ArDriveCheckBoxState>(find.byType(ArDriveCheckBox));

    expect(stateAfterTap.state, CheckBoxState.checked);

    expect(find.byWidget(checkbox), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('CheckBox should not change its state when disabled',
      (tester) async {
    const checkbox = ArDriveCheckBox(
      title: 'Title',
      key: Key('checkbox'),
      isDisabled: true,
      useNewIcons: false,
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(
          home: checkbox,
        ),
      ),
    );

    /// Gets the container to tap
    final findCheckBox = find.byType(AnimatedContainer).first;

    final state =
        tester.state<ArDriveCheckBoxState>(find.byType(ArDriveCheckBox));

    /// Should be `normal` because we initialized it without `checked`
    expect(state.state, CheckBoxState.disabled);

    await tester.ensureVisible(findCheckBox);
    await tester.pumpAndSettle();
    await tester.tap(findCheckBox);

    /// After tap it should not change the state
    final stateAfterTap =
        tester.state<ArDriveCheckBoxState>(find.byType(ArDriveCheckBox));

    expect(stateAfterTap.state, CheckBoxState.disabled);
  });
  testWidgets(
      'CheckBox should not change its state when isIndeterminate is true',
      (tester) async {
    const checkbox = ArDriveCheckBox(
      title: 'Title',
      key: Key('checkbox'),
      isIndeterminate: true,
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(
          home: checkbox,
        ),
      ),
    );

    /// Gets the container to tap
    final findCheckBox = find.byType(ArDriveIcon).first;

    final state =
        tester.state<ArDriveCheckBoxState>(find.byType(ArDriveCheckBox));

    /// Should be `indeterminate` because we initialized it without `checked`
    expect(state.state, CheckBoxState.indeterminate);

    await tester.ensureVisible(findCheckBox);
    await tester.pumpAndSettle();
    await tester.tap(findCheckBox);

    /// After tap it should not change the state
    final stateAfterTap =
        tester.state<ArDriveCheckBoxState>(find.byType(ArDriveCheckBox));

    expect(stateAfterTap.state, CheckBoxState.indeterminate);
  });

  group('to the keyboard and a screen reader', () {
    // It was a bare GestureDetector: the mouse could tick it, Tab could not
    // reach it, and a screen reader did not know it was a checkbox.
    testWidgets('Tab reaches it, and Space ticks and unticks it',
        (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: ArDriveCheckBox(
              semanticLabel: 'Photos',
              onChange: changes.add,
            ),
          ),
        ),
      ));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(changes, [true, false]);
    });

    testWidgets('is announced as a checkbox with its state and label',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(ArDriveApp(
        builder: (context) => const MaterialApp(
          home: Scaffold(
            body: ArDriveCheckBox(semanticLabel: 'Photos', checked: true),
          ),
        ),
      ));

      expect(
        tester.getSemantics(find.byType(ArDriveCheckBox)),
        matchesSemantics(
          label: 'Photos',
          hasCheckedState: true,
          isChecked: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('a disabled one is announced as disabled and takes no tap',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(ArDriveApp(
        builder: (context) => const MaterialApp(
          home: Scaffold(
            body: ArDriveCheckBox(semanticLabel: 'Photos', isDisabled: true),
          ),
        ),
      ));

      expect(
        tester.getSemantics(find.byType(ArDriveCheckBox)),
        matchesSemantics(
          label: 'Photos',
          hasCheckedState: true,
          hasEnabledState: true,
        ),
      );
      semantics.dispose();
    });
  });

  group('follows its caller', () {
    // It read `checked` once, so callers keyed it by its state; a tick
    // rebuilt it and threw its keyboard focus away.
    Widget harness() {
      var checked = false;
      return ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  ArDriveCheckBox(
                    semanticLabel: 'Photos',
                    checked: checked,
                    onChange: (value) => setState(() => checked = value),
                  ),
                  ElevatedButton(onPressed: () {}, child: const Text('next')),
                ],
              ),
            ),
          ),
        ),
      );
    }

    bool isChecked(WidgetTester tester) => tester
        .state<ArDriveCheckBoxState>(find.byType(ArDriveCheckBox))
        .checked;

    testWidgets('Space twice ticks then unticks it, and focus stays',
        (tester) async {
      await tester.pumpWidget(harness());

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus;
      expect(focused?.debugLabel, 'ArDriveCheckBox');

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(isChecked(tester), isTrue);
      expect(FocusManager.instance.primaryFocus, same(focused));

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(isChecked(tester), isFalse);
      expect(FocusManager.instance.primaryFocus, same(focused));
    });

    testWidgets('a tick the caller refuses goes back', (tester) async {
      await tester.pumpWidget(ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ArDriveCheckBox(
                checked: false,
                // Refused: the caller rebuilds and still says false.
                onChange: (_) => setState(() {}),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.byType(ArDriveCheckBox));
      await tester.pump();

      expect(isChecked(tester), isFalse);
    });

    testWidgets('a change from outside is shown', (tester) async {
      Widget box(bool checked) => ArDriveApp(
            builder: (context) => MaterialApp(
              home: Scaffold(body: ArDriveCheckBox(checked: checked)),
            ),
          );

      await tester.pumpWidget(box(false));
      await tester.pumpWidget(box(true));

      expect(isChecked(tester), isTrue);
    });
  });

  testWidgets('a titled box is announced once', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => const MaterialApp(
        home: Scaffold(
          body: ArDriveCheckBox(title: 'Upload with thumbnails'),
        ),
      ),
    ));

    expect(
      tester.getSemantics(find.byType(ArDriveCheckBox)),
      matchesSemantics(
        label: 'Upload with thumbnails',
        hasCheckedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('keyboard focus draws a ring, and the pointer does not',
      (tester) async {
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => const MaterialApp(
        home: Scaffold(body: ArDriveCheckBox(semanticLabel: 'Photos')),
      ),
    ));

    Color ring() => ((tester
                .widget<DecoratedBox>(
                    find.byKey(const Key('checkboxFocusRing')))
                .decoration as BoxDecoration)
            .border! as Border)
        .top
        .color;

    expect(ring(), Colors.transparent);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(ring(), ArDriveColorTokens.darkMode().textHigh);
  });

  testWidgets('a box out of the Tab order is skipped, and still ticks',
      (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: Scaffold(
          body: ArDriveCheckBox(
            semanticLabel: 'Photos',
            inTabOrder: false,
            onChange: changes.add,
          ),
        ),
      ),
    ));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        isNot('ArDriveCheckBox'));

    await tester.tap(find.byType(ArDriveCheckBox));
    expect(changes, [true]);
  });
}
