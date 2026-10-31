import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // On a phone the end of a long revealed password ran under the eye.
  for (final toggle in [false, true]) {
    testWidgets(
        'a long value stops a gap short of the '
        '${toggle ? 'built-in eye' : 'suffix icon'}', (tester) async {
      const suffixKey = Key('suffix');
      await tester.pumpWidget(
        ArDriveApp(
          builder: (context) => MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                child: ArDriveTextFieldNew(
                  controller: TextEditingController(
                      text: 'alpha bravo charlie delta echo foxtrot coast'),
                  showObfuscationToggle: toggle,
                  obscureText: false,
                  suffixIcon: toggle
                      ? null
                      : const SizedBox(key: suffixKey, width: 20, height: 20),
                ),
              ),
            ),
          ),
        ),
      );
      final input = tester.getRect(find.byType(EditableText));
      final suffix = tester
          .getRect(toggle ? find.byType(ArDriveIcon) : find.byKey(suffixKey));
      expect(
          suffix.left - input.right, greaterThanOrEqualTo(ArDriveSpacing.xs));
    });
  }
}
