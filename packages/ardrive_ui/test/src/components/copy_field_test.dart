import 'dart:ui' show SemanticsFlag;

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const secret = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopQ';

  Widget wrap(Widget child) => ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(home: Scaffold(body: child)),
      );

  Widget artifact({
    required bool isSecret,
    String text = secret,
    bool alignsWithSecret = false,
  }) =>
      ArDriveCopyField(
        label: 'Access key',
        text: text,
        copyLabel: 'Copy',
        copiedLabel: 'Copied!',
        copyFailedLabel: "Couldn't copy",
        revealLabel: 'Show access key',
        isSecret: isSecret,
        alignsWithSecret: alignsWithSecret,
      );

  /// The obscured state lives on the design system's own field, so read it
  /// from there rather than from anything this component owns.
  bool isObscured(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).obscureText;

  group('ArDriveCopyField', () {
    testWidgets('a key is drawn in monospace, a link in the body face',
        (tester) async {
      Widget field({required bool isMonospace}) => ArDriveCopyField(
            label: 'Access key',
            text: secret,
            copyLabel: 'Copy',
            copiedLabel: 'Copied!',
            copyFailedLabel: "Couldn't copy",
            isMonospace: isMonospace,
          );
      String? family(WidgetTester tester) => tester
          .widget<EditableText>(find.byType(EditableText))
          .style
          .fontFamily;

      await tester.pumpWidget(wrap(field(isMonospace: true)));
      expect(family(tester), ArDriveMonospace.family);

      await tester.pumpWidget(wrap(field(isMonospace: false)));
      await tester.pump();
      expect(family(tester), isNot(ArDriveMonospace.family));
    });

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

    double fieldWidth(WidgetTester tester) =>
        tester.getSize(find.byType(ArDriveTextFieldNew)).width;

    testWidgets('a plain field beside a secret is the same width as it',
        (tester) async {
      // A dialog stacks a link over a key. The reveal control only exists on
      // the secret one, so unless its slot is held open on both, the two boxes
      // render at visibly different widths.
      await tester
          .pumpWidget(wrap(artifact(isSecret: false, alignsWithSecret: true)));
      final plain = fieldWidth(tester);

      await tester.pumpWidget(wrap(artifact(isSecret: true)));
      final secret = fieldWidth(tester);

      expect(secret, plain);
    });

    testWidgets('a plain field on its own keeps no gap for a reveal control',
        (tester) async {
      // A link with no key anywhere has nothing to line up with, and the held
      // slot only pushed Copy away from the field.
      await tester.pumpWidget(wrap(artifact(isSecret: false)));
      final alone = fieldWidth(tester);

      await tester.pumpWidget(wrap(artifact(isSecret: true)));
      final secret = fieldWidth(tester);

      expect(alone, greaterThan(secret));
    });

    testWidgets('a screen reader hears the label with the field, once',
        (tester) async {
      // The label is drawn above the field rather than by it, so it has to be
      // handed back to the field for assistive technology.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(artifact(isSecret: false, text: 'abc')));

      expect(find.bySemanticsLabel(RegExp('Access key')), findsOneWidget);
      final node =
          tester.getSemantics(find.bySemanticsLabel(RegExp('Access key')));
      expect(node.hasFlag(SemanticsFlag.isTextField), isTrue,
          reason: 'the label names the field itself, not a separate text');
      handle.dispose();
    });

    testWidgets('the value stays intact underneath the mask', (tester) async {
      // Masking is a display concern. If it ever reached the controller the
      // sharer would hand out a string of dots.
      await tester.pumpWidget(wrap(artifact(isSecret: true)));

      final field = tester.widget<EditableText>(find.byType(EditableText));

      expect(field.controller.text, secret);
    });
  });

  group('ArDriveCopyField copying', () {
    final copies = <String>[];
    var refuse = false;

    setUp(() {
      copies.clear();
      refuse = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          if (refuse) throw PlatformException(code: 'refused');
          copies.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('copies the value, even while it is masked', (tester) async {
      await tester.pumpWidget(wrap(artifact(isSecret: true)));

      await tester.tap(find.text('Copy'));
      await tester.pump();

      expect(copies, [secret]);
      expect(find.text('Copied!'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Copied!'), findsNothing);
    });

    testWidgets('says so when the browser refuses the copy', (tester) async {
      refuse = true;
      await tester.pumpWidget(wrap(artifact(isSecret: false)));

      await tester.tap(find.text('Copy'));
      await tester.pump();

      expect(find.text("Couldn't copy"), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Copy is a keyboard-reachable action', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(artifact(isSecret: false)));

      expect(
          tester.getSemantics(find.byType(ArDriveLink)),
          matchesSemantics(
            label: 'Copy',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            hasTapAction: true,
          ));
      handle.dispose();
    });
  });

  testWidgets('the reveal control tells a screen reader whether the key shows',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap(artifact(isSecret: true)));

    SemanticsNode reveal() => tester.getSemantics(find.byType(IconButton));

    expect(
        reveal(),
        matchesSemantics(
          label: 'Show access key',
          isButton: true,
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
        ));

    await tester.tap(find.byType(IconButton));
    await tester.pump();

    expect(reveal().hasFlag(SemanticsFlag.isToggled), isTrue);
    expect(tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isFalse);
    handle.dispose();
  });
}
