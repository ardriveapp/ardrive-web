import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// IDs, addresses and keys are drawn in Roboto Mono at their final width
/// from the first frame, so nothing beside them moves when the face, which
/// loads on demand, replaces the narrower fallback.
void main() {
  const address = 'abc123...xyz9';

  Widget wrap(Widget child, {double textScale = 1}) => ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      );

  TextStyle codeStyle(WidgetTester tester) =>
      ArDriveTypographyNew.of(tester.element(find.byType(Scaffold))).code();

  group('ArDriveIdText', () {
    testWidgets('is Roboto Mono at its final width', (tester) async {
      await tester.pumpWidget(wrap(
        Builder(
          builder: (context) => ArDriveIdText(
            address,
            style: ArDriveTypographyNew.of(context).code(),
          ),
        ),
      ));

      final style = codeStyle(tester);
      expect(
        tester.getSize(find.byType(ArDriveIdText)).width,
        ArDriveMonospace.widthOf(address, style.fontSize!),
      );
      expect(
        tester.widget<Text>(find.text(address)).style!.fontFamily,
        ArDriveMonospace.family,
      );
    });

    testWidgets('grows with the reader\'s text size', (tester) async {
      await tester.pumpWidget(wrap(
        Builder(
          builder: (context) => ArDriveIdText(
            address,
            style: ArDriveTypographyNew.of(context).code(),
          ),
        ),
        textScale: 1.5,
      ));

      final style = codeStyle(tester);
      expect(
        tester.getSize(find.byType(ArDriveIdText)).width,
        ArDriveMonospace.widthOf(address, style.fontSize!,
            textScaler: const TextScaler.linear(1.5)),
      );
    });
  });

  group('ArDriveIdText.spansIn', () {
    const idStyle = TextStyle(fontSize: 11);

    test('sets the ID apart from the words around it', () {
      final spans =
          ArDriveIdText.spansIn('By $address today', address, idStyle: idStyle);

      expect(spans, hasLength(3));
      expect((spans[0] as TextSpan).text, 'By ');
      final id = (spans[1] as WidgetSpan).child as ArDriveIdText;
      expect(id.text, address);
      expect(id.style, idStyle);
      expect((spans[2] as TextSpan).text, ' today');
    });

    test('an ID at either end leaves no empty span', () {
      expect(
          ArDriveIdText.spansIn('$address owns it', address, idStyle: idStyle),
          hasLength(2));
      expect(
          ArDriveIdText.spansIn('Owner: $address', address, idStyle: idStyle),
          hasLength(2));
    });

    test('text without the ID is one plain span', () {
      final spans = ArDriveIdText.spansIn('By Ada', address, idStyle: idStyle);

      expect(spans, hasLength(1));
      expect((spans.single as TextSpan).text, 'By Ada');
    });
  });

  group('ArDriveLink in monospace', () {
    testWidgets('is sized to its final width, icon included', (tester) async {
      late TextStyle style;
      await tester.pumpWidget(wrap(
        Builder(builder: (context) {
          style = ArDriveTypographyNew.of(context).code();
          return ArDriveLink(
            text: address,
            style: style,
            external: true,
            onTap: () {},
          );
        }),
      ));

      final fontSize = style.fontSize!;
      final expected = ArDriveMonospace.widthOf(address, fontSize) +
          (ArDriveSpacing.xxs + fontSize * 1.1).ceilToDouble();
      expect(tester.getSize(find.byType(ArDriveLink)).width, expected);
    });

    testWidgets('a link in the body face keeps its own width', (tester) async {
      await tester.pumpWidget(wrap(
        ArDriveLink(text: 'Learn more', onTap: () {}),
      ));

      expect(
        find.descendant(
          of: find.byType(ArDriveLink),
          matching: find.byWidgetPredicate(
              (w) => w is SizedBox && w.width != null && w.width! > 0),
        ),
        findsNothing,
      );
    });
  });

  group('ArDriveTextFieldNew with an ID style', () {
    testWidgets('draws in monospace, at the height of a plain field',
        (tester) async {
      await tester.pumpWidget(wrap(
        Builder(
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                key: const Key('id'),
                width: 300,
                child: ArDriveTextFieldNew(
                  initialValue: 'e5d0d4c2-1f1c-4d7a-9b1e-2a3c4d5e6f70',
                  textStyle: ArDriveTypographyNew.of(context).code(),
                ),
              ),
              const SizedBox(
                key: Key('name'),
                width: 300,
                child: ArDriveTextFieldNew(
                  initialValue: 'My drive',
                ),
              ),
            ],
          ),
        ),
      ));

      final editables =
          tester.widgetList<EditableText>(find.byType(EditableText)).toList();
      expect(editables[0].style.fontFamily, ArDriveMonospace.family);
      expect(editables[1].style.fontFamily, isNot(ArDriveMonospace.family));
      expect(
        tester.getSize(find.byKey(const Key('id'))).height,
        tester.getSize(find.byKey(const Key('name'))).height,
      );
    });
  });
}
