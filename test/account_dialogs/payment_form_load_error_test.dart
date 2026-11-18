import 'package:ardrive/turbo/topup/blocs/payment_form/payment_form_bloc.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/turbo/topup/views/topup_payment_form.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockTurbo extends Mock implements Turbo {}

/// The card form says the countries could not load in the form itself, with
/// Try again, not in a second dialog on top of the top-up. The form's Stripe
/// card field cannot be built in a test, so this drives the notice the form
/// shows (PaymentFormLoadError) with the real bloc behind it.
void main() {
  testWidgets(
      'a failed countries load is a notice with Try again, and the '
      'retry clears it', (tester) async {
    final turbo = _MockTurbo();
    var calls = 0;
    when(() => turbo.maxQuoteExpirationDate)
        .thenReturn(DateTime.now().add(const Duration(days: 1)));
    when(() => turbo.getSupportedCountries()).thenAnswer((_) async {
      calls++;
      if (calls == 1) throw Exception('offline');
      return ['Canada'];
    });
    final bloc = PaymentFormBloc(
      turbo,
      PriceEstimate(
        estimate: PriceForFiat(
          winc: BigInt.from(10),
          adjustments: const [],
          actualPaymentAmount: null,
          quotedPaymentAmount: null,
        ),
        priceInCurrency: 10,
        estimatedStorage: 1,
      ),
      mockExpirationTimeInSeconds: (_) => 60,
    );
    addTearDown(bloc.close);

    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BlocProvider<PaymentFormBloc>.value(
            value: bloc,
            child: const PaymentFormLoadError(),
          ),
        ),
      ),
    ));

    bloc.add(PaymentFormLoadSupportedCountries());
    await tester.pump();
    await tester.pump();

    expect(find.byType(ArDriveNotice), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();

    expect(calls, 2);
    expect(find.byType(ArDriveNotice), findsNothing);
  });
}
