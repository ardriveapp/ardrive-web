import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<GlobalKey<ArDriveFormNewState>> pumpForm(
    WidgetTester tester, {
    required String first,
    required String second,
  }) async {
    final key = GlobalKey<ArDriveFormNewState>();
    String? required(String? value) =>
        value == null || value.isEmpty ? 'Required' : null;

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: ArDriveFormNew(
              key: key,
              child: Column(
                children: [
                  ArDriveTextFieldNew(
                    controller: TextEditingController(text: first),
                    validator: required,
                  ),
                  ArDriveTextFieldNew(
                    controller: TextEditingController(text: second),
                    validator: required,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return key;
  }

  testWidgets('a form with an empty required field is not valid',
      (tester) async {
    final key = await pumpForm(tester, first: 'filled', second: '');

    expect(key.currentState!.validateSync(), isFalse);
  });

  testWidgets('a form with every field filled is valid', (tester) async {
    final key = await pumpForm(tester, first: 'filled', second: 'also');

    expect(key.currentState!.validateSync(), isTrue);
  });
}
