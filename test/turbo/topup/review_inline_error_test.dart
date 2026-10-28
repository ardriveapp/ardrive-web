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

/// A failed card payment is shown in the review itself, with the way back to
/// the card details. It used to open a second dialog over this one.
void main() {
  setUpAll(() {
    registerFallbackValue(const TurboTopUpShowPaymentFormView(2));
  });

  testWidgets('a failed payment is a notice in the review, not a dialog',
      (tester) async {
    final review = _MockReviewBloc();
    final flow = _MockFlowBloc();
    whenListen(
      review,
      const Stream<PaymentReviewState>.empty(),
      initialState: PaymentReviewPaymentError(
        errorType: TurboErrorType.unknown,
        quoteExpirationDate: DateTime.now().add(const Duration(minutes: 20)),
        total: '25.00',
        subTotal: null,
        credits: '4.6037',
        promoDiscount: null,
        creditsWinc: BigInt.from(4603700000000),
        currentBalance: BigInt.from(8847800000000),
      ),
    );
    whenListen(flow, const Stream<TurboTopupFlowState>.empty(),
        initialState: const TurboTopupFlowInitial());
    tester.view.physicalSize = const Size(1200, 1400);
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

    final notice = find.widgetWithText(ArDriveNotice, 'Edit card details');
    expect(notice, findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    // Confirm & Pay waits for new card details.
    final pay = tester.widget<ArDriveButtonNew>(
      find.widgetWithText(ArDriveButtonNew, 'Confirm & Pay'),
    );
    expect(pay.isDisabled || pay.onPressed == null, isTrue);

    await tester.tap(find.text('Edit card details'));
    verify(() => flow.add(const TurboTopUpShowPaymentFormView(2))).called(1);
  });
}
