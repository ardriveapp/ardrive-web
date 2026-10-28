import 'package:ardrive/turbo/topup/components/country_picker.dart';
import 'package:ardrive/turbo/topup/components/quote_timer.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(800, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ArDriveApp(
    builder: (context) => MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    ),
  ));
}

void main() {
  group('QuoteTimer', () {
    testWidgets('shows how long the quote has left', (tester) async {
      await _pump(
        tester,
        QuoteTimer(secondsLeft: 125, onRefresh: () {}),
      );

      expect(find.text('Price valid for 02:05'), findsOneWidget);
    });

    testWidgets('says the quote expired once past, and reports it once',
        (tester) async {
      var expired = 0;
      await _pump(
        tester,
        QuoteTimer(
          expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
          onRefresh: () {},
          onExpired: () => expired++,
        ),
      );

      expect(find.text('Quote expired'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(expired, 1);
    });

    testWidgets('shows a failed quote in place of the countdown',
        (tester) async {
      await _pump(
        tester,
        QuoteTimer(
          secondsLeft: 60,
          errorMessage: 'Unable to update quote',
          onRefresh: () {},
        ),
      );

      expect(find.text('Unable to update quote'), findsOneWidget);
      expect(find.textContaining('Price valid for'), findsNothing);
    });

    testWidgets('refresh is a named button that asks for a new quote',
        (tester) async {
      final handle = tester.ensureSemantics();
      var refreshed = 0;
      await _pump(
        tester,
        QuoteTimer(secondsLeft: 60, onRefresh: () => refreshed++),
      );

      final refresh = find.bySemanticsLabel('Refresh quote');
      expect(
        tester.getSemantics(refresh),
        matchesSemantics(
          isButton: true,
          hasTapAction: true,
          label: 'Refresh quote',
        ),
      );

      await tester.tap(refresh);
      expect(refreshed, 1);
      handle.dispose();
    });

    testWidgets('shows a spinner in place of refresh while loading',
        (tester) async {
      await _pump(
        tester,
        QuoteTimer(secondsLeft: 60, isLoading: true, onRefresh: () {}),
      );

      expect(find.byType(ArDriveSpinner), findsOneWidget);
      expect(find.byTooltip('Refresh quote'), findsNothing);
    });
  });

  group('CountryPicker', () {
    const countries = [
      'United States',
      'United Kingdom',
      'Germany',
      'France',
      'Tunisia',
    ];

    test('filters ignoring case, prefix matches first', () {
      expect(
        CountryPicker.filter(countries, 'UNI'),
        ['United States', 'United Kingdom', 'Tunisia'],
      );
      expect(CountryPicker.filter(countries, ''), countries);
      expect(CountryPicker.filter(countries, 'zz'), isEmpty);
    });

    Future<List<String?>> pumpPicker(WidgetTester tester) async {
      final chosen = <String?>[];
      await _pump(
        tester,
        SizedBox(
          width: 400,
          child: CountryPicker(
            countries: countries,
            onChanged: chosen.add,
          ),
        ),
      );
      return chosen;
    }

    testWidgets('narrows the list as you type', (tester) async {
      await pumpPicker(tester);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('Germany'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'uni');
      await tester.pumpAndSettle();

      expect(find.text('United States'), findsOneWidget);
      expect(find.text('United Kingdom'), findsOneWidget);
      expect(find.text('Tunisia'), findsOneWidget);
      expect(find.text('Germany'), findsNothing);
    });

    testWidgets('a tap picks a country', (tester) async {
      final chosen = await pumpPicker(tester);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'ger');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Germany'));
      await tester.pumpAndSettle();

      expect(chosen.last, 'Germany');
      expect(find.widgetWithText(TextField, 'Germany'), findsOneWidget);
    });

    testWidgets('the arrow keys and Enter pick a country', (tester) async {
      final chosen = await pumpPicker(tester);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'uni');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(chosen.last, 'United Kingdom');
    });

    testWidgets('Enter picks the first match', (tester) async {
      final chosen = await pumpPicker(tester);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'fr');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(chosen.last, 'France');
    });

    testWidgets('the list opens under the field, and Escape closes it',
        (tester) async {
      await pumpPicker(tester);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'fr');
      await tester.pumpAndSettle();

      final fieldBottom = tester.getBottomLeft(find.byType(TextField)).dy;
      final optionTop = tester.getTopLeft(find.text('France').last).dy;
      expect(optionTop - fieldBottom, inInclusiveRange(0, 20));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('text that names no country leaves none chosen',
        (tester) async {
      final chosen = await pumpPicker(tester);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'germany');
      await tester.pumpAndSettle();
      expect(chosen.last, 'Germany');

      await tester.enterText(find.byType(TextField), 'germanyx');
      await tester.pumpAndSettle();
      expect(chosen.last, isNull);
    });
  });
}
