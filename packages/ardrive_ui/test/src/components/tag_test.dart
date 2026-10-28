import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(body: Center(child: child)),
        ),
      );

  final tokens = ArDriveColorTokens.darkMode();

  group('ArDriveTag', () {
    BoxDecoration decorationOf(WidgetTester tester) => tester
        .widget<Container>(find.descendant(
            of: find.byType(ArDriveTag), matching: find.byType(Container)))
        .decoration! as BoxDecoration;

    Color textColour(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text)).style!.color!;

    testWidgets('neutral is a quiet fill, mid text and no edge',
        (tester) async {
      await tester.pumpWidget(wrap(const ArDriveTag(text: 'Deployment')));

      final decoration = decorationOf(tester);
      expect(decoration.color, tokens.containerL3);
      expect(decoration.border, isNull);
      expect(decoration.borderRadius, BorderRadius.circular(ArDriveRadius.sm));
      expect(textColour(tester, 'Deployment'), tokens.textMid);
    });

    testWidgets('info and success take the brand status colours',
        (tester) async {
      final expected = {
        ArDriveTagType.info: (tokens.statusInfoContainer, tokens.statusInfoFg),
        ArDriveTagType.success: (
          tokens.statusSuccessContainer,
          tokens.statusSuccessFg,
        ),
      };
      for (final MapEntry(key: type, value: (fill, fg)) in expected.entries) {
        await tester.pumpWidget(wrap(ArDriveTag(text: 'x', type: type)));
        expect(decorationOf(tester).color, fill, reason: '$type');
        expect(textColour(tester, 'x'), fg, reason: '$type');
      }
    });

    testWidgets('one size: caption, semi-bold', (tester) async {
      await tester.pumpWidget(wrap(const ArDriveTag(text: 'Shared')));

      final style = tester.widget<Text>(find.text('Shared')).style!;
      final caption =
          ArDriveTypographyNew.of(tester.element(find.text('Shared')))
              .caption();
      expect(style.fontSize, caption.fontSize);
      expect(style.fontWeight, FontWeight.w600);
    });

    testWidgets('a leading icon in the text colour', (tester) async {
      await tester.pumpWidget(wrap(const ArDriveTag(
        text: '20% off',
        type: ArDriveTagType.success,
        icon: Icons.local_offer,
      )));

      final icon = tester.widget<Icon>(find.byIcon(Icons.local_offer));
      expect(icon.color, tokens.statusSuccessFg);
      expect(icon.size, ArDriveTag.iconSize);
    });

    testWidgets('ellipsizes rather than overflows', (tester) async {
      await tester.pumpWidget(wrap(const SizedBox(
        width: 60,
        child: ArDriveTag(text: 'a-very-long-name.ar.io', icon: Icons.link),
      )));

      expect(tester.takeException(), isNull);
    });
  });

  group('ArDriveStatusText', () {
    Color textColour(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text)).style!.color!;

    testWidgets('error is red, text and icon', (tester) async {
      await tester.pumpWidget(wrap(const ArDriveStatusText(
        text: 'Lease ends in 12 days',
        type: ArDriveStatusType.error,
      )));

      expect(textColour(tester, 'Lease ends in 12 days'), tokens.statusErrorFg);
      final icon = tester.widget<ArDriveIcon>(find.byType(ArDriveIcon));
      expect(icon.icon, ArDriveIconsData.close_circle);
      expect(icon.color, tokens.statusErrorFg);
    });

    testWidgets('warning is neutral text with the warning icon',
        (tester) async {
      await tester.pumpWidget(wrap(const ArDriveStatusText(
        text: 'Details differ',
        type: ArDriveStatusType.warning,
      )));

      expect(textColour(tester, 'Details differ'), tokens.textMid);
      final icon = tester.widget<ArDriveIcon>(find.byType(ArDriveIcon));
      expect(icon.icon, ArDriveIconsData.triangle);
      expect(icon.color, tokens.textMid,
          reason: 'the brand has no warning colour');
    });

    testWidgets('info and success take the brand hues', (tester) async {
      for (final (type, fg, glyph) in [
        (ArDriveStatusType.info, tokens.statusInfoFg, ArDriveIconsData.info),
        (
          ArDriveStatusType.success,
          tokens.statusSuccessFg,
          ArDriveIconsData.check_cirle,
        ),
      ]) {
        await tester.pumpWidget(wrap(ArDriveStatusText(text: 'x', type: type)));
        expect(textColour(tester, 'x'), fg, reason: '$type');
        expect(
          tester.widget<ArDriveIcon>(find.byType(ArDriveIcon)).icon,
          glyph,
          reason: '$type',
        );
      }
    });

    testWidgets('neutral is words alone', (tester) async {
      await tester.pumpWidget(wrap(const ArDriveStatusText(
        text: 'Checking',
        type: ArDriveStatusType.neutral,
      )));

      expect(find.byType(ArDriveIcon), findsNothing);
      expect(textColour(tester, 'Checking'), tokens.textMid);
    });

    testWidgets('read as one sentence', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(wrap(const ArDriveStatusText(
        text: 'Verified',
        type: ArDriveStatusType.success,
      )));

      expect(find.bySemanticsLabel('Verified'), findsOneWidget);
      semantics.dispose();
    });
  });
}
