import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Test if TextField renders', (tester) async {
    const textField = ArDriveTextField();
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => const MaterialApp(
        home: Scaffold(body: textField),
      ),
    ));

    expect(find.byWidget(textField), findsOneWidget);
  });

  testWidgets('Test if the state is unfocus', (tester) async {
    const textField = ArDriveTextField();

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(
          home: Scaffold(body: textField),
        ),
      ),
    );

    final state =
        tester.state<ArDriveTextFieldState>(find.byType(ArDriveTextField));

    expect(state.textFieldState, TextFieldState.unfocused);
  });

  testWidgets('Test validation message change the correct state',
      (tester) async {
    final textField = ArDriveTextField(
      /// success if more than 10 chars in ther other case error
      asyncValidator: (s) => s != null && s.length > 10 ? null : 'error',
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(body: textField),
        ),
      ),
    );

    final findTextField = find.byType(TextFormField);

    await tester.enterText(findTextField, 'any test with more than 10');

    final state =
        tester.state<ArDriveTextFieldState>(find.byType(ArDriveTextField));

    expect(state.textFieldState, TextFieldState.success);

    await tester.enterText(findTextField, 'fail');

    expect(state.textFieldState, TextFieldState.error);
  });

  testWidgets(
      'Should  show the AnimatedTextFieldLabel when there is a error message and the state is error',
      (tester) async {
    final textField = ArDriveTextField(
      validator: (s) => 'error label', // always show error\
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(body: textField),
        ),
      ),
    );

    final findTextField = find.byType(ArDriveTextField);

    await tester.enterText(findTextField, 'error');

    await tester.pumpAndSettle(const Duration(milliseconds: 3000));

    final label = find.bySubtype<AnimatedTextFieldLabel>();

    await tester.ensureVisible(label);

    expect(findTextField, findsOneWidget);
    expect(find.text('error label'), findsOneWidget);
  });

  testWidgets(
      'Should  show the AnimatedTextFieldLabel when there is a success message and the state is success',
      (tester) async {
    final textField = ArDriveTextField(
      successMessage: 'Success message',
      validator: (s) => null, // always show success
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(body: textField),
        ),
      ),
    );
    final findTextField = find.byType(TextFormField);

    await tester.enterText(findTextField, 'error');

    await tester.pumpAndSettle(const Duration(milliseconds: 3000));

    final label = find.bySubtype<AnimatedTextFieldLabel>().at(0);

    await tester.ensureVisible(label);

    final state =
        tester.state<ArDriveTextFieldState>(find.byType(ArDriveTextField));

    expect(findTextField, findsOneWidget);
    expect(find.text('Success message'), findsOneWidget);
    expect(state.textFieldState, TextFieldState.success);
  });

  testWidgets('Should  show the TextFieldLabel when there is a label message',
      (tester) async {
    const textField = ArDriveTextField(
      label: 'Label',
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(
          home: Scaffold(body: textField),
        ),
      ),
    );

    expect(find.byWidget(textField), findsOneWidget);
    expect(find.bySubtype<TextFieldLabel>(), findsOneWidget);
    expect(find.text('Label'), findsOneWidget);
  });

  testWidgets(
      'Should not show the TextFieldLabel when there isnt a label message',
      (tester) async {
    const textField = ArDriveTextField();

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(
          home: Scaffold(body: textField),
        ),
      ),
    );

    expect(find.byWidget(textField), findsOneWidget);
    expect(find.bySubtype<TextFieldLabel>(), findsNothing);
    expect(find.text('Label'), findsNothing);
  });
}
