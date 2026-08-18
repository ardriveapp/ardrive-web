import 'package:ardrive/components/copyable_share_artifact.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const secret = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopQ';

  Widget wrap(Widget child) => ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(home: Scaffold(body: child)),
      );

  Widget artifact({required bool isSecret}) => CopyableShareArtifact(
        label: 'Access key',
        controller: TextEditingController(text: secret),
        text: secret,
        copyLabel: 'Copy',
        revealLabel: 'Show access key',
        isSecret: isSecret,
      );

  /// The obscured state lives on the design system's own field, so read it
  /// from there rather than from anything this component owns.
  bool isObscured(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).obscureText;

  group('CopyableShareArtifact', () {
    testWidgets('a secret artifact starts masked', (tester) async {
      await tester.pumpWidget(wrap(artifact(isSecret: true)));

      expect(isObscured(tester), isTrue);
    });

    testWidgets('a non-secret artifact is never masked', (tester) async {
      await tester.pumpWidget(wrap(artifact(isSecret: false)));

      expect(isObscured(tester), isFalse);
    });

    testWidgets('a non-secret artifact offers no reveal control',
        (tester) async {
      // A public link has nothing to hide, and a toggle that does nothing is
      // one more thing to explain.
      await tester.pumpWidget(wrap(artifact(isSecret: false)));

      expect(find.byTooltip('Show access key'), findsNothing);
    });

    testWidgets(
        'the reveal toggle works even though the field is read only - '
        'a mask the sharer cannot lift would be a dead end', (tester) async {
      // The field is `isEnabled: false` so the value cannot be edited, and a
      // disabled field swallows taps on its own decoration - which is why the
      // design system's built-in `showObfuscationToggle` cannot be used here.
      // This asserts the replacement control is actually reachable.
      await tester.pumpWidget(wrap(artifact(isSecret: true)));

      expect(isObscured(tester), isTrue);

      await tester.tap(find.byTooltip('Show access key'));
      await tester.pump();

      expect(isObscured(tester), isFalse);

      // And back, so the sharer can re-hide it without closing the dialog.
      await tester.tap(find.byTooltip('Show access key'));
      await tester.pump();

      expect(isObscured(tester), isTrue);
    });

    testWidgets('the value stays intact underneath the mask', (tester) async {
      // Masking is a display concern. If it ever reached the controller the
      // sharer would hand out a string of dots.
      await tester.pumpWidget(wrap(artifact(isSecret: true)));

      final field = tester.widget<EditableText>(find.byType(EditableText));

      expect(field.controller.text, secret);
    });
  });
}
