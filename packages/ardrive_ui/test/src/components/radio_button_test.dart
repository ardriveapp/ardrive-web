import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('RadioButton renders', (tester) async {
    const radioButton = ArDriveRadioButton(
      text: 'Some text',
    );
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => const MaterialApp(
        home: radioButton,
      ),
    ));

    expect(find.byWidget(radioButton), findsOneWidget);
    expect(find.text('Some text'), findsOneWidget);
  });

  testWidgets('Test if RadioButton gets the correct state after interacting',
      (tester) async {
    /// Starts with radio button off
    const radioButton = ArDriveRadioButton(
      text: 'text',
      value: false,
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(
          home: Scaffold(body: radioButton),
        ),
      ),
    );

    final findRadio = find.byType(AnimatedContainer).first;

    /// Taps the radio button
    await tester.tap(findRadio);

    final state =
        tester.state<ArDriveRadioButtonState>(find.byType(ArDriveRadioButton));

    /// should be checked
    expect(state.state, RadioButtonState.checked);

    /// taps again
    await tester.tap(findRadio);

    /// should be unchecked
    expect(state.state, RadioButtonState.unchecked);
  });

  testWidgets('Should not change its state when disabled', (tester) async {
    /// Starts with radio button off
    const radioButton = ArDriveRadioButton(
      text: 'text',
      value: false,
      isEnabled: false,
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(
          home: Scaffold(body: radioButton),
        ),
      ),
    );

    final findRadio = find.byType(AnimatedContainer).first;

    /// Taps the radio button
    await tester.tap(findRadio);

    final state =
        tester.state<ArDriveRadioButtonState>(find.byType(ArDriveRadioButton));

    /// should be disabled
    expect(state.state, RadioButtonState.disabled);
  });
  group('Testing ArDriveRadioButtonGroup', () {
    testWidgets('should render ArDriveRadioButtonGroup with 3 elements',
        (tester) async {
      /// Starts with radio button off
      final options = [
        RadioButtonOptions(text: 'one'),
        RadioButtonOptions(text: 'two'),
        RadioButtonOptions(text: 'three'),
      ];

      final radioButtonGroup = ArDriveRadioButtonGroup(
        options: options,
        builder: (i, button) => button,
      );

      await tester.pumpWidget(
        ArDriveApp(
          builder: (context) => MaterialApp(
            home: Scaffold(body: radioButtonGroup),
          ),
        ),
      );

      expect(find.byType(ArDriveRadioButton), findsNWidgets(3));
    });
    testWidgets('Should check the RadioButton tapped', (tester) async {
      /// Starts with radio button off
      final options = [
        RadioButtonOptions(text: 'one'),
        RadioButtonOptions(text: 'two'),
        RadioButtonOptions(text: 'three'),
      ];

      final radioButtonGroup = ArDriveRadioButtonGroup(
        options: options,
        builder: (i, button) => button,
      );

      await tester.pumpWidget(
        ArDriveApp(
          builder: (context) => MaterialApp(
            home: Scaffold(body: radioButtonGroup),
          ),
        ),
      );

      /// Tap the RadioButton with index 1
      final radioButton = find.byType(ArDriveRadioButton).at(1);
      final radioButtonClick = find.byType(GestureDetector).at(1);

      /// Taps the radio button
      await tester.tap(radioButtonClick);

      final state = tester.state<ArDriveRadioButtonState>(radioButton);

      /// should be enabled
      expect(state.state, RadioButtonState.checked);
    });
  });
}
