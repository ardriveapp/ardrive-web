import 'package:ardrive/turbo/models/payment_user_information.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/blocs/payment_review/payment_review_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/models/payment_model.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:flutter_stripe/flutter_stripe.dart' show StripeException;
import 'package:flutter_stripe/flutter_stripe.dart' as stripe;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockTurbo extends Mock implements Turbo {}

/// A failed card payment is told apart by cause, so the message can say
/// whether the card was charged.
void main() {
  final info = PaymentUserInformation.create(
    name: 'name',
    country: 'country',
    userAcceptedToReceiveEmails: false,
  );

  setUpAll(() => registerFallbackValue(info));

  Future<TurboErrorType> errorTypeFor(Object thrown) async {
    final turbo = MockTurbo();
    when(() => turbo.createPaymentIntent(
          amount: any(named: 'amount'),
          currency: any(named: 'currency'),
        )).thenAnswer((_) async => PaymentModel(
          paymentSession: PaymentSession(clientSecret: 's', id: 'i'),
          topUpQuote: TopUpQuote(
            currencyType: 'usd',
            destinationAddress: 'a',
            destinationAddressType: 'address',
            paymentAmount: 1000,
            quotedPaymentAmount: 1000,
            paymentProvider: 'stripe',
            quoteExpirationDate: DateTime(1234).toIso8601String(),
            quoteId: 'q',
            winstonCreditAmount: '10000000000000',
          ),
          adjustments: [],
        ));
    when(() => turbo.paymentUserInformation).thenReturn(info);
    when(() => turbo.quoteExpirationDate)
        .thenReturn(DateTime.now().add(const Duration(minutes: 5)));
    when(() => turbo.getBalance()).thenAnswer((_) async => BigInt.one);
    when(() => turbo.confirmPayment()).thenThrow(thrown);

    final bloc = PaymentReviewBloc(
      turbo,
      PriceEstimate(
        priceInCurrency: 100,
        estimate: PriceForFiat(
          winc: BigInt.from(10000000000000),
          adjustments: const [],
          actualPaymentAmount: null,
          quotedPaymentAmount: null,
        ),
        estimatedStorage: 1,
      ),
    );
    addTearDown(bloc.close);

    final failed =
        bloc.stream.firstWhere((s) => s is PaymentReviewPaymentError);
    bloc.add(PaymentReviewLoadPaymentModel());
    await bloc.stream.firstWhere((s) => s is PaymentReviewPaymentModelLoaded);
    bloc.add(const PaymentReviewFinishPayment());
    return ((await failed) as PaymentReviewPaymentError).errorType;
  }

  StripeException stripeError(stripe.FailureCode code) => StripeException(
        error: stripe.LocalizedErrorMessage(code: code),
      );

  test('a declined card is a payment failure', () async {
    expect(await errorTypeFor(stripeError(stripe.FailureCode.Failed)),
        TurboErrorType.paymentFailed);
  });

  test('an abandoned card check is canceled', () async {
    expect(await errorTypeFor(stripeError(stripe.FailureCode.Canceled)),
        TurboErrorType.paymentCanceled);
  });

  test('anything else leaves the outcome unknown', () async {
    expect(
        await errorTypeFor(Exception('socket closed')), TurboErrorType.unknown);
  });
}
