import 'package:ardrive_ui_library/ardrive_ui_library.dart';
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

      validator: (s) => s != null && s.length > 10,
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
      'Should not show the AnimatedTextFieldLabel when there isnt a error message',
      (tester) async {
    final textField = ArDriveTextField(
      validator: (s) => false, // always show error
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(body: textField),
        ),
      ),
    );

    final findTextField = find.byType(TextFormField);

    await tester.enterText(findTextField, 'any test to fail');

    final state =
        tester.state<ArDriveTextFieldState>(find.byType(ArDriveTextField));

    expect(findTextField, findsOneWidget);

    expect(find.bySubtype<AnimatedTextFieldLabel>(), findsNothing);
    expect(state.textFieldState, TextFieldState.error);
  });

  testWidgets(
      'Should  show the AnimatedTextFieldLabel when there is a error message and the state is error',
      (tester) async {
    final textField = ArDriveTextField(
      errorMessage: 'Error message',
      validator: (s) => false, // always show error\
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(body: textField),
        ),
      ),
    );

    final findTextField = find.byType(TextFormField);

    await tester.enterText(findTextField, 'any test to fail');

    final state =
        tester.state<ArDriveTextFieldState>(find.byType(ArDriveTextField));

    expect(findTextField, findsOneWidget);
    expect(find.bySubtype<AnimatedTextFieldLabel>(), findsOneWidget);
    expect(find.text('Error message'), findsOneWidget);
    expect(state.textFieldState, TextFieldState.error);
  });

  testWidgets(
      'Should not show the AnimatedTextFieldLabel when there isnt a success message and the state is success',
      (tester) async {
    final textField = ArDriveTextField(
      validator: (s) => true, // always show success
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(body: textField),
        ),
      ),
    );

    final findTextField = find.byType(TextFormField);

    await tester.enterText(findTextField, 'any text to success');

    final state =
        tester.state<ArDriveTextFieldState>(find.byType(ArDriveTextField));

    expect(findTextField, findsOneWidget);
    expect(find.bySubtype<AnimatedTextFieldLabel>(), findsNothing);
    expect(state.textFieldState, TextFieldState.success);
  });

  testWidgets(
      'Should  show the AnimatedTextFieldLabel when there is a success message and the state is success',
      (tester) async {
    final textField = ArDriveTextField(
      successMessage: 'Success message',
      validator: (s) => true, // always show success
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(body: textField),
        ),
      ),
    );

    final findTextField = find.byType(TextFormField);

    await tester.enterText(findTextField, 'any text to success');

    final state =
        tester.state<ArDriveTextFieldState>(find.byType(ArDriveTextField));

    expect(findTextField, findsOneWidget);
    expect(find.bySubtype<AnimatedTextFieldLabel>(), findsOneWidget);
    expect(state.textFieldState, TextFieldState.success);
    expect(find.text('Success message'), findsOneWidget);
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
