import 'package:ardrive/turbo/models/payment_user_information.dart';
import 'package:ardrive/turbo/topup/blocs/payment_review/payment_review_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/models/payment_model.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockTurbo extends Mock implements Turbo {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakePaymentUserInformation());
  });

  final mockPaymentSession = PaymentSession(
    clientSecret: 'clientSecret',
    id: 'paymentIntentId',
  );

  final mockTopUpQuote = TopUpQuote(
    currencyType: 'usd',
    destinationAddress: 'destinationAddress',
    destinationAddressType: 'address',
    paymentAmount: 100,
    paymentProvider: 'stripe',
    quoteExpirationDate: DateTime.now().toIso8601String(),
    quoteId: 'quoteId',
    winstonCreditAmount: '5000',
  );

  group('PaymentReviewBloc', () {
    late Turbo mockTurbo;
    late PaymentReviewBloc paymentReviewBloc;
    late PriceEstimate mockPriceEstimate;

    group('PaymentReviewLoadPaymentModel', () {
      setUp(() {
        mockTurbo = MockTurbo();
        mockPriceEstimate = PriceEstimate(
            priceInCurrency: 100,
            credits: BigInt.from(100),
            estimatedStorage: 1);
        paymentReviewBloc = PaymentReviewBloc(mockTurbo, mockPriceEstimate);
      });

      blocTest<PaymentReviewBloc, PaymentReviewState>(
        'emits [PaymentReviewLoadingPaymentModel, PaymentReviewPaymentModelLoaded]',
        build: () => paymentReviewBloc,
        act: (bloc) => bloc.add(PaymentReviewLoadPaymentModel()),
        setUp: () {
          when(
            () => mockTurbo.createPaymentIntent(
              amount: any(named: 'amount'),
              currency: any(named: 'currency'),
            ),
          ).thenAnswer(
            (invocation) => Future.value(
              PaymentModel(
                paymentSession: mockPaymentSession,
                topUpQuote: mockTopUpQuote,
              ),
            ),
          );

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
        },
        expect: () => [
          const PaymentReviewLoadingPaymentModel(),
          // You should adjust the expected states and the returned values to your specific use case.
          PaymentReviewPaymentModelLoaded(
            quoteExpirationDate: DateTime.now(),
            total: '10.00',
            subTotal: '10.00',
            credits: '10',
          ),
        ],
      );

      blocTest<PaymentReviewBloc, PaymentReviewState>(
        'emits [PaymentReviewLoadingPaymentModel, PaymentReviewErrorLoadingPaymentModel] when ',
        build: () => paymentReviewBloc,
        act: (bloc) => bloc.add(PaymentReviewLoadPaymentModel()),
        setUp: () {
          when(
            () => mockTurbo.createPaymentIntent(
              amount: any(named: 'amount'),
              currency: any(named: 'currency'),
            ),
          ).thenThrow(Exception());

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
        },
        expect: () => [
          const PaymentReviewLoadingPaymentModel(),
          const PaymentReviewErrorLoadingPaymentModel(
            errorType: TurboErrorType.unknown,
          )
        ],
      );
    });
    group('PaymentReviewFinishPayment', () {
      setUp(() {
        mockTurbo = MockTurbo();
        mockPriceEstimate = PriceEstimate(
            priceInCurrency: 100,
            credits: BigInt.from(100),
            estimatedStorage: 1);
        paymentReviewBloc = PaymentReviewBloc(mockTurbo, mockPriceEstimate);
      });

      blocTest<PaymentReviewBloc, PaymentReviewState>(
        'emits [PaymentReviewLoadingPaymentModel, PaymentReviewPaymentSuccess]',
        build: () => paymentReviewBloc,
        act: (bloc) async {
          bloc.add(PaymentReviewLoadPaymentModel());
          await Future.delayed(const Duration(milliseconds: 100));
          bloc.add(PaymentReviewFinishPayment(
              paymentUserInformation: FakePaymentUserInformation()));
        },
        setUp: () {
          when(
            () => mockTurbo.createPaymentIntent(
              amount: any(named: 'amount'),
              currency: any(named: 'currency'),
            ),
          ).thenAnswer(
            (invocation) => Future.value(
              PaymentModel(
                  paymentSession: mockPaymentSession,
                  topUpQuote: mockTopUpQuote),
            ),
          );

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
          when(
            () => mockTurbo.confirmPayment(
              userInformation: any(named: 'userInformation'),
            ),
          ).thenAnswer(
            (invocation) => Future.value(
              PaymentStatus.success,
            ),
          );

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
        },
        expect: () => [
          const PaymentReviewLoadingPaymentModel(),
          isA<PaymentReviewPaymentModelLoaded>(),
          isA<PaymentReviewLoading>(),
          isA<PaymentReviewPaymentSuccess>(),
        ],
      );

      blocTest<PaymentReviewBloc, PaymentReviewState>(
        'emits [PaymentReviewLoadingPaymentModel, PaymentReviewError] when turbo throws creating the payment intent',
        build: () => paymentReviewBloc,
        act: (bloc) async {
          bloc.add(PaymentReviewLoadPaymentModel());
          await Future.delayed(const Duration(milliseconds: 100));
          bloc.add(PaymentReviewFinishPayment(
              paymentUserInformation: FakePaymentUserInformation()));
        },
        setUp: () {
          when(
            () => mockTurbo.createPaymentIntent(
              amount: any(named: 'amount'),
              currency: any(named: 'currency'),
            ),
          ).thenAnswer(
            (invocation) => Future.value(
              PaymentModel(
                  paymentSession: mockPaymentSession,
                  topUpQuote: mockTopUpQuote),
            ),
          );

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
          when(
            () => mockTurbo.confirmPayment(
              userInformation: any(named: 'userInformation'),
            ),
          ).thenThrow(Exception());

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
        },
        expect: () => [
          const PaymentReviewLoadingPaymentModel(),
          isA<PaymentReviewPaymentModelLoaded>(),
          isA<PaymentReviewLoading>(),
          isA<PaymentReviewPaymentError>(),
        ],
      );
      blocTest<PaymentReviewBloc, PaymentReviewState>(
        'emits [PaymentReviewLoadingPaymentModel, PaymentReviewError] when turbo returns a paymetn status failed',
        build: () => paymentReviewBloc,
        act: (bloc) async {
          bloc.add(PaymentReviewLoadPaymentModel());
          await Future.delayed(const Duration(milliseconds: 100));
          bloc.add(PaymentReviewFinishPayment(
              paymentUserInformation: FakePaymentUserInformation()));
        },
        setUp: () {
          when(
            () => mockTurbo.createPaymentIntent(
              amount: any(named: 'amount'),
              currency: any(named: 'currency'),
            ),
          ).thenAnswer(
            (invocation) => Future.value(
              PaymentModel(
                  paymentSession: mockPaymentSession,
                  topUpQuote: mockTopUpQuote),
            ),
          );

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
          when(
            () => mockTurbo.confirmPayment(
              userInformation: any(named: 'userInformation'),
            ),
          ).thenAnswer((invocation) => Future.value(PaymentStatus.failed));

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
        },
        expect: () => [
          const PaymentReviewLoadingPaymentModel(),
          isA<PaymentReviewPaymentModelLoaded>(),
          isA<PaymentReviewLoading>(),
          isA<PaymentReviewPaymentError>(),
        ],
      );
      blocTest<PaymentReviewBloc, PaymentReviewState>(
        'emits [PaymentReviewLoadingPaymentModel, PaymentReviewError] when turbo returns a paymetn status quoteExpired',
        build: () => paymentReviewBloc,
        act: (bloc) async {
          bloc.add(PaymentReviewLoadPaymentModel());
          await Future.delayed(const Duration(milliseconds: 100));
          bloc.add(PaymentReviewFinishPayment(
              paymentUserInformation: FakePaymentUserInformation()));
        },
        setUp: () {
          when(
            () => mockTurbo.createPaymentIntent(
              amount: any(named: 'amount'),
              currency: any(named: 'currency'),
            ),
          ).thenAnswer(
            (invocation) => Future.value(
              PaymentModel(
                  paymentSession: mockPaymentSession,
                  topUpQuote: mockTopUpQuote),
            ),
          );

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
          when(
            () => mockTurbo.confirmPayment(
              userInformation: any(named: 'userInformation'),
            ),
          ).thenAnswer(
              (invocation) => Future.value(PaymentStatus.quoteExpired));

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
        },
        expect: () => [
          const PaymentReviewLoadingPaymentModel(),
          isA<PaymentReviewPaymentModelLoaded>(),
          isA<PaymentReviewLoading>(),
          isA<PaymentReviewPaymentError>(),
        ],
      );
    });

    group('PaymentReviewRefreshQuote', () {
      setUp(() {
        mockTurbo = MockTurbo();
        mockPriceEstimate = PriceEstimate(
            priceInCurrency: 100,
            credits: BigInt.from(100),
            estimatedStorage: 1);
        paymentReviewBloc = PaymentReviewBloc(mockTurbo, mockPriceEstimate);
      });
      blocTest<PaymentReviewBloc, PaymentReviewState>(
        'emits [PaymentReviewLoadingPaymentModel, PaymentReviewPaymentModelLoaded] when turbo returns a payment model',
        build: () => paymentReviewBloc,
        act: (bloc) async {
          bloc.add(PaymentReviewLoadPaymentModel());
          await Future.delayed(const Duration(milliseconds: 100));
          bloc.add(PaymentReviewRefreshQuote());
        },
        setUp: () {
          when(
            () => mockTurbo.createPaymentIntent(
              amount: any(named: 'amount'),
              currency: any(named: 'currency'),
            ),
          ).thenAnswer(
            (invocation) => Future.value(
              PaymentModel(
                  paymentSession: mockPaymentSession,
                  topUpQuote: mockTopUpQuote),
            ),
          );

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
        },
        expect: () => [
          isA<PaymentReviewLoadingPaymentModel>(),
          isA<PaymentReviewPaymentModelLoaded>(),
          isA<PaymentReviewLoadingQuote>(),
          isA<PaymentReviewQuoteLoaded>(),
        ],
      );
      blocTest<PaymentReviewBloc, PaymentReviewState>(
        'emits [PaymentReviewLoadingPaymentModel, PaymentReviewError] when turbo throws an exception',
        build: () => paymentReviewBloc,
        act: (bloc) async {
          when(
            () => mockTurbo.createPaymentIntent(
              amount: any(named: 'amount'),
              currency: any(named: 'currency'),
            ),
          ).thenAnswer(
            (invocation) => Future.value(
              PaymentModel(
                  paymentSession: mockPaymentSession,
                  topUpQuote: mockTopUpQuote),
            ),
          );
          bloc.add(PaymentReviewLoadPaymentModel());
          await Future.delayed(const Duration(milliseconds: 100));
          when(
            () => mockTurbo.createPaymentIntent(
              amount: any(named: 'amount'),
              currency: any(named: 'currency'),
            ),
          ).thenThrow(Exception());
          bloc.add(PaymentReviewRefreshQuote());
        },
        setUp: () {
          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
        },
        expect: () => [
          isA<PaymentReviewLoadingPaymentModel>(),
          isA<PaymentReviewPaymentModelLoaded>(),
          isA<PaymentReviewLoadingQuote>(),
          isA<PaymentReviewQuoteError>(),
        ],
      );
    });
  });
}

class FakePaymentUserInformation extends Fake
    implements PaymentUserInformation {}
