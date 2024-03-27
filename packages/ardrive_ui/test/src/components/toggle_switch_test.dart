import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ToggleSwitch widget and its contents render', (tester) async {
    const toggleSwitch = ArDriveToggleSwitch(
      text: 'some text',
    );
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => const MaterialApp(
        home: toggleSwitch,
      ),
    ));

    expect(find.byWidget(toggleSwitch), findsOneWidget);
  });
  testWidgets('ToggleSwitch initialize with the correct state', (tester) async {
    const toggleSwitchOn = ArDriveToggleSwitch(
      value: true,
      text: 'some text',
    );
    const toggleSwitchOff = ArDriveToggleSwitch(
      value: false,
      text: 'some text',
    );
    const toggleSwitchDisabled = ArDriveToggleSwitch(
      value: true,
      isEnabled: false,
      text: 'some text',
    );

    // on
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => const MaterialApp(
        home: toggleSwitchOn,
      ),
    ));

    final state =
        tester.state<ArDriveToggleSwitchState>(find.byWidget(toggleSwitchOn));

    expect(state.state, ToggleState.on);

    // off
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => const MaterialApp(
        home: toggleSwitchOff,
      ),
    ));
    await tester.ensureVisible(find.byWidget(toggleSwitchOff));
    await tester.pumpAndSettle();

    final stateOff =
        tester.state<ArDriveToggleSwitchState>(find.byWidget(toggleSwitchOff));

    expect(stateOff.state, ToggleState.off);

    expect(find.byWidget(toggleSwitchOff), findsOneWidget);

    // disabled
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => const MaterialApp(
        home: toggleSwitchDisabled,
      ),
    ));

    await tester.ensureVisible(find.byWidget(toggleSwitchDisabled));
    await tester.pumpAndSettle();

    final stateDisabled = tester
        .state<ArDriveToggleSwitchState>(find.byWidget(toggleSwitchDisabled));

    expect(stateDisabled.state, ToggleState.disabled);

    expect(find.byWidget(toggleSwitchDisabled), findsOneWidget);
  });

  testWidgets(
      'Check if ToggleSwitch change its state correctly with interaction',
      (tester) async {
    late bool onChangedValue;

    final toggleSwitch = ArDriveToggleSwitch(
      text: 'some text',
      onChanged: (value) {
        onChangedValue = value;
      },
    );

    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: toggleSwitch,
      ),
    ));

    // check if state is off
    final findWidgetToTap = find.byType(AnimatedContainer).first;

    final toggle = find.byWidget(toggleSwitch);
    final state = tester.state<ArDriveToggleSwitchState>(toggle);

    // initially it is `off`
    expect(state.state, ToggleState.off);

    await tester.ensureVisible(findWidgetToTap);
    await tester.pumpAndSettle();
    await tester.tap(findWidgetToTap);

    /// After tap it should be the `on` state
    final stateAfterTap = tester.state<ArDriveToggleSwitchState>(toggle);

    expect(stateAfterTap.state, ToggleState.on);

    // verifies if the `onChanged` function is called
    expect(true, onChangedValue);
  });

  testWidgets(
      'Check if ToggleSwitch change does not change its state when disabled',
      (tester) async {
    bool? onChangedValue;

    final toggleSwitch = ArDriveToggleSwitch(
      text: 'some text',
      isEnabled: false,
      onChanged: (value) {
        onChangedValue = value;
      },
    );

    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: toggleSwitch,
      ),
    ));

    final findWidgetToTap = find.byType(AnimatedContainer).first;

    final toggle = find.byWidget(toggleSwitch);
    final state = tester.state<ArDriveToggleSwitchState>(toggle);

    // check if state is `disabled`
    expect(state.state, ToggleState.disabled);

    await tester.ensureVisible(findWidgetToTap);
    await tester.pumpAndSettle();
    await tester.tap(findWidgetToTap);

    /// After tap it should be keep the same state
    final stateAfterTap = tester.state<ArDriveToggleSwitchState>(toggle);

    expect(stateAfterTap.state, ToggleState.disabled);

    // should not change the value of the variable
    expect(onChangedValue, null);
  });
}
