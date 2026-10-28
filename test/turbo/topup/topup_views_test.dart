import 'package:ardrive/turbo/topup/components/amount_mode_toggle.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive/turbo/topup/views/topup_success_view.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => ArDriveApp(
      builder: (context) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  group('TurboTopupScaffold', () {
    testWidgets('is the standard dialog, with its title and actions',
        (tester) async {
      var backs = 0;

      await tester.pumpWidget(_app(TurboTopupScaffold(
        title: 'Payment details',
        description: 'This is a one-time payment, powered by Stripe.',
        actions: [ModalAction.dismiss(title: 'Back', action: () => backs++)],
        child: const Text('Form'),
      )));

      expect(find.byType(ArDriveStandardModalNew), findsOneWidget);
      expect(find.text('Payment details'), findsOneWidget);
      expect(
        find.text('This is a one-time payment, powered by Stripe.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Back'));
      expect(backs, 1);
    });

    testWidgets('offers no close while a payment is under way', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_app(const TurboTopupScaffold(
        title: 'Processing',
        canClose: false,
        child: Text('Working'),
      )));

      expect(find.bySemanticsLabel('Close'), findsNothing);
      handle.dispose();
    });
  });

  group('AmountModeToggle', () {
    Future<void> pump(WidgetTester tester, String currency) =>
        tester.pumpWidget(_app(AmountModeToggle(
          selectedMode: AmountMode.currency,
          currencyLabel: currency,
          onModeChanged: (_) {},
        )));

    testWidgets('shows a dollar sign for USD', (tester) async {
      await pump(tester, 'USD');
      expect(find.byIcon(Icons.attach_money), findsOneWidget);
    });

    /// SOL and ETH were shown with a dollar sign.
    testWidgets('shows no dollar sign for a token', (tester) async {
      await pump(tester, 'SOL');
      expect(find.byIcon(Icons.attach_money), findsNothing);
      expect(find.byIcon(Icons.toll_outlined), findsOneWidget);
    });

    testWidgets('tells a screen reader which mode is chosen', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, 'USD');

      expect(
        tester.getSemantics(find.text('USD')),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          isFocusable: true,
          label: 'USD',
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('TurboSuccessView', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(const TurboSuccessView(
        amountPaid: '\$25.00',
        creditsReceived: '4.5970',
        storageEstimate: '311.1 MB',
        newBalanceCredits: '8.8400 credits',
        newBalanceStorage: '598.7 MB',
      )));
      // Lets the confetti run out.
      await tester.pump(const Duration(seconds: 6));
    }

    testWidgets('leads with the credits added as a Light figure',
        (tester) async {
      await pump(tester);

      final figure = tester.widget<Text>(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.textSpan?.toPlainText() ?? '') == '4.5970 credits added',
        ),
      );
      final first = (figure.textSpan! as TextSpan).children!.first;
      expect(first.style!.fontWeight, ArFontWeight.light.weight);
      expect(find.text('~311.1 MB'), findsOneWidget);
      expect(find.byType(ArDriveNotice), findsOneWidget);
    });

    testWidgets('writes credits in lowercase after an amount', (tester) async {
      await pump(tester);

      expect(find.text('8.8400 credits'), findsOneWidget);
      expect(find.textContaining('Credits'), findsNothing);
    });
  });
}
