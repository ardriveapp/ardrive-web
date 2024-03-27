import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
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
}
