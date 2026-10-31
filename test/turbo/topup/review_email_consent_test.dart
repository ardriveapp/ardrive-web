import 'package:ardrive/turbo/topup/blocs/payment_review/payment_review_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/views/topup_review_view.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockReviewBloc extends MockBloc<PaymentReviewEvent, PaymentReviewState>
    implements PaymentReviewBloc {}

class _MockFlowBloc extends MockBloc<TurboTopupFlowEvent, TurboTopupFlowState>
    implements TurboTopupFlowBloc {}

/// Typing a receipt email must not opt the buyer in to news and promotions.
void main() {
  setUpAll(() {
    registerFallbackValue(const PaymentReviewFinishPayment());
  });

  testWidgets('a typed email does not tick the news opt-in', (tester) async {
    final review = _MockReviewBloc();
    final flow = _MockFlowBloc();
    whenListen(
      review,
      const Stream<PaymentReviewState>.empty(),
      initialState: PaymentReviewPaymentModelLoaded(
        total: '25.00',
        subTotal: null,
        credits: '4.6037',
        promoDiscount: null,
        quoteExpirationDate: DateTime.now().add(const Duration(minutes: 20)),
        creditsWinc: BigInt.from(4603700000000),
        currentBalance: BigInt.from(8847800000000),
        storageEstimate: '1.0 GB',
        currentBalanceStorage: '1.0 GB',
        newBalanceStorage: '2.0 GB',
      ),
    );
    whenListen(flow, const Stream<TurboTopupFlowState>.empty(),
        initialState: const TurboTopupFlowInitial());
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PaymentReviewBloc>.value(value: review),
              BlocProvider<TurboTopupFlowBloc>.value(value: flow),
            ],
            child: const TurboReviewView(),
          ),
        ),
      ),
    ));
    await tester.pump();

    await tester.enterText(find.byType(EditableText).first, 'a@b.co');
    await tester.pump();

    await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Confirm & Pay'));
    await tester.pump();

    final event = verify(() => review.add(captureAny())).captured.single
        as PaymentReviewFinishPayment;
    expect(event.email, 'a@b.co');
    expect(event.userAcceptedToReceiveEmails, isFalse);
  });
}
