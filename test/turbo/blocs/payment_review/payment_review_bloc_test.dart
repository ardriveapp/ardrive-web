import 'package:ardrive/turbo/models/payment_user_information.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
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
  final mockPaymentUserInformation = PaymentUserInformation.create(
    name: 'name',
    country: 'country',
    userAcceptedToReceiveEmails: false,
  );

  setUpAll(() {
    registerFallbackValue(mockPaymentUserInformation);
  });

  final mockPaymentSession = PaymentSession(
    clientSecret: 'clientSecret',
    id: 'paymentIntentId',
  );

  final mockDate = DateTime(1234).toIso8601String();

  final mockTopUpQuote = TopUpQuote(
    currencyType: 'usd',
    destinationAddress: 'destinationAddress',
    destinationAddressType: 'address',
    paymentAmount: 1000,
    quotedPaymentAmount: 1000,
    paymentProvider: 'stripe',
    quoteExpirationDate: mockDate,
    quoteId: 'quoteId',
    winstonCreditAmount: '10000000000000',
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
          estimate: PriceForFiat(
            winc: BigInt.from(10000000000000),
            adjustments: const [],
            actualPaymentAmount: null,
            quotedPaymentAmount: null,
          ),
          estimatedStorage: 1,
        );
        paymentReviewBloc = PaymentReviewBloc(
          mockTurbo,
          mockPriceEstimate,
        );
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
                adjustments: [],
              ),
            ),
          );

          when(() => mockTurbo.paymentUserInformation).thenReturn(
            mockPaymentUserInformation,
          );

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
            (invocation) => DateTime(1234).add(const Duration(minutes: 5)),
          );
        },
        expect: () => [
          const PaymentReviewLoadingPaymentModel(),
          // You should adjust the expected states and the returned values to your specific use case.
          PaymentReviewPaymentModelLoaded(
            quoteExpirationDate: DateTime(1234).add(const Duration(minutes: 5)),
            total: '10.00',
            subTotal: '10.00',
            credits: '10.0000',
            promoDiscount: null,
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

          when(() => mockTurbo.paymentUserInformation).thenReturn(
            mockPaymentUserInformation,
          );

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
          estimate: PriceForFiat(
            winc: BigInt.from(100),
            adjustments: const [],
            actualPaymentAmount: null,
            quotedPaymentAmount: null,
          ),
          estimatedStorage: 1,
        );
        paymentReviewBloc = PaymentReviewBloc(
          mockTurbo,
          mockPriceEstimate,
        );
      });

      blocTest<PaymentReviewBloc, PaymentReviewState>(
        'emits [PaymentReviewLoadingPaymentModel, PaymentReviewPaymentSuccess]',
        build: () => paymentReviewBloc,
        act: (bloc) async {
          bloc.add(PaymentReviewLoadPaymentModel());
          await Future.delayed(const Duration(milliseconds: 100));
          bloc.add(const PaymentReviewFinishPayment());
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
                topUpQuote: mockTopUpQuote,
                adjustments: [],
              ),
            ),
          );
          when(() => mockTurbo.paymentUserInformation).thenReturn(
            mockPaymentUserInformation,
          );

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
          when(
            () => mockTurbo.confirmPayment(),
          ).thenAnswer(
            (invocation) => Future.value(
              PaymentStatus.success,
            ),
          );

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
        },
        expect: () => [
          isA<PaymentReviewLoadingPaymentModel>(),
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
          bloc.add(const PaymentReviewFinishPayment());
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
                topUpQuote: mockTopUpQuote,
                adjustments: [],
              ),
            ),
          );
          when(() => mockTurbo.paymentUserInformation).thenReturn(
            mockPaymentUserInformation,
          );

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
          when(
            () => mockTurbo.confirmPayment(),
          ).thenThrow(Exception());

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
        },
        expect: () => [
          isA<PaymentReviewLoadingPaymentModel>(),
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
          bloc.add(const PaymentReviewFinishPayment());
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
                topUpQuote: mockTopUpQuote,
                adjustments: [],
              ),
            ),
          );
          when(() => mockTurbo.paymentUserInformation).thenReturn(
            mockPaymentUserInformation,
          );

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
          when(
            () => mockTurbo.confirmPayment(),
          ).thenAnswer((invocation) => Future.value(PaymentStatus.failed));

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
        },
        expect: () => [
          isA<PaymentReviewLoadingPaymentModel>(),
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
          bloc.add(const PaymentReviewFinishPayment());
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
                topUpQuote: mockTopUpQuote,
                adjustments: [],
              ),
            ),
          );
          when(() => mockTurbo.paymentUserInformation).thenReturn(
            mockPaymentUserInformation,
          );
          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
          when(
            () => mockTurbo.confirmPayment(),
          ).thenAnswer(
              (invocation) => Future.value(PaymentStatus.quoteExpired));

          when(() => mockTurbo.quoteExpirationDate).thenAnswer(
              (invocation) => DateTime.now().add(const Duration(minutes: 5)));
        },
        expect: () => [
          isA<PaymentReviewLoadingPaymentModel>(),
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
          estimate: PriceForFiat(
            winc: BigInt.from(100),
            adjustments: const [],
            actualPaymentAmount: null,
            quotedPaymentAmount: null,
          ),
          estimatedStorage: 1,
        );
        paymentReviewBloc = PaymentReviewBloc(
          mockTurbo,
          mockPriceEstimate,
        );
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
                topUpQuote: mockTopUpQuote,
                adjustments: [],
              ),
            ),
          );
          when(() => mockTurbo.paymentUserInformation).thenReturn(
            mockPaymentUserInformation,
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
                topUpQuote: mockTopUpQuote,
                adjustments: [],
              ),
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
          when(() => mockTurbo.paymentUserInformation).thenReturn(
            mockPaymentUserInformation,
          );
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
