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

  Widget artifact({required bool isSecret, String text = secret}) =>
      CopyableShareArtifact(
        label: 'Access key',
        text: text,
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

    testWidgets('a synchronously available value is shown, not swallowed',
        (tester) async {
      // The component owns its controller precisely so this holds. When each
      // dialog filled a controller from a bloc listener instead, a cubit that
      // reached success synchronously - which the public drive path does -
      // never fired the listener, and the field rendered empty.
      await tester.pumpWidget(wrap(artifact(isSecret: false, text: 'a-link')));

      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'a-link',
      );
    });

    testWidgets('revealing one secret does not reveal the next',
        (tester) async {
      // Ticking "include the key in the link" swaps the value underneath a
      // revealed field. The new value must start masked again.
      await tester.pumpWidget(wrap(artifact(isSecret: true)));

      await tester.tap(find.byTooltip('Show access key'));
      await tester.pump();

      expect(isObscured(tester), isFalse);

      await tester.pumpWidget(
        wrap(artifact(isSecret: true, text: 'a-different-secret')),
      );
      await tester.pump();

      expect(isObscured(tester), isTrue);
    });

    testWidgets('a secret and a plain field are the same width',
        (tester) async {
      // A dialog stacks a link over a key. The reveal control only exists on
      // the secret one, so unless its slot is held open on both, the two boxes
      // render at visibly different widths.
      double fieldWidth(WidgetTester tester) =>
          tester.getSize(find.byType(ArDriveTextFieldNew)).width;

      await tester.pumpWidget(wrap(artifact(isSecret: false)));
      final plain = fieldWidth(tester);

      await tester.pumpWidget(wrap(artifact(isSecret: true)));
      final secret = fieldWidth(tester);

      expect(secret, plain);
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
