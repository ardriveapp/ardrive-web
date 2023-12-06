import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/blocs/payment_form/payment_form_bloc.dart';
import 'package:ardrive/turbo/topup/models/payment_model.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockTurbo extends Mock implements Turbo {}

void main() {
  late MockTurbo mockTurbo;
  late PaymentFormBloc paymentFormBloc;
  late PriceEstimate initialPriceEstimate;

  group('PaymentFormBloc', () {
    setUp(() {
      mockTurbo = MockTurbo();
      initialPriceEstimate = PriceEstimate(
        estimate: PriceForFiat(
          winc: BigInt.from(10),
          adjustments: const [],
          actualPaymentAmount: null,
          quotedPaymentAmount: null,
        ),
        priceInCurrency: 10,
        estimatedStorage: 1,
      );
      when(() => mockTurbo.maxQuoteExpirationDate).thenAnswer(
          (invocation) => DateTime.now().add(const Duration(days: 1)));
      paymentFormBloc = PaymentFormBloc(
        mockTurbo,
        initialPriceEstimate,
        mockExpirationTimeInSeconds: (DateTime d) => 1234,
      );
    });

    group('PaymentFormUpdateQuote', () {
      setUp(() {
        mockTurbo = MockTurbo();
        final initialPriceEstimate = PriceEstimate(
          estimate: PriceForFiat(
            winc: BigInt.from(10),
            adjustments: const [],
            actualPaymentAmount: null,
            quotedPaymentAmount: null,
          ),
          priceInCurrency: 10,
          estimatedStorage: 1,
        );
        when(() => mockTurbo.maxQuoteExpirationDate).thenAnswer(
            (invocation) => DateTime.now().add(const Duration(days: 1)));
        paymentFormBloc = PaymentFormBloc(mockTurbo, initialPriceEstimate);
      });

      blocTest<PaymentFormBloc, PaymentFormState>(
        'Emits [PaymentFormLoadingQuote], then [PaymentFormQuoteLoaded] when PaymentFormUpdateQuote is added and refreshPriceEstimate succeeds',
        build: () {
          when(() => mockTurbo.refreshPriceEstimate()).thenAnswer(
            (_) async => PriceEstimate(
              estimate: PriceForFiat(
                winc: BigInt.from(15),
                adjustments: const [],
                actualPaymentAmount: null,
                quotedPaymentAmount: null,
              ),
              priceInCurrency: 15,
              estimatedStorage: 1.5,
            ),
          );
          when(() => mockTurbo.getSupportedCountries())
              .thenAnswer((invocation) => Future.value([
                    'US',
                  ]));

          return paymentFormBloc;
        },
        act: (bloc) async {
          bloc.add(PaymentFormLoadSupportedCountries());
          await Future.delayed(const Duration(microseconds: 100));
          bloc.add(PaymentFormUpdateQuote());
        },
        expect: () => [
          isA<PaymentFormLoading>(),
          isA<PaymentFormLoaded>(),
          isA<PaymentFormLoadingQuote>(),
          isA<PaymentFormQuoteLoaded>(),
        ],
      );

      blocTest<PaymentFormBloc, PaymentFormState>(
        'Emits [PaymentFormQuoteLoadFailure], then remains unchanged when PaymentFormUpdateQuote is added and refreshPriceEstimate throws',
        build: () {
          when(() => mockTurbo.getSupportedCountries())
              .thenAnswer((invocation) => Future.value([
                    'US',
                  ]));
          when(() => mockTurbo.refreshPriceEstimate()).thenThrow(Exception());
          return paymentFormBloc;
        },
        act: (bloc) async {
          bloc.add(PaymentFormLoadSupportedCountries());
          await Future.delayed(const Duration(microseconds: 100));
          bloc.add(PaymentFormUpdateQuote());
        },
        expect: () => [
          isA<PaymentFormLoading>(),
          isA<PaymentFormLoaded>(),
          isA<PaymentFormLoadingQuote>(),
          isA<PaymentFormQuoteLoadFailure>(),
        ],
      );
    });

    group('PaymentFormLoadSupportedCountries', () {
      blocTest<PaymentFormBloc, PaymentFormState>(
        'emits [PaymentFormLoading, PaymentFormLoaded] when PaymentFormLoadSupportedCountries event is added',
        build: () => paymentFormBloc,
        act: (bloc) {
          when(() => mockTurbo.getSupportedCountries())
              .thenAnswer((_) => Future.value(['Country A', 'Country B']));
          bloc.add(PaymentFormLoadSupportedCountries());
        },
        expect: () => [
          isA<PaymentFormLoading>(),
          PaymentFormLoaded(
            initialPriceEstimate,
            1234,
            const ['Country A', 'Country B'],
          ),
        ],
      );
      blocTest<PaymentFormBloc, PaymentFormState>(
        'emits [PaymentFormLoading, PaymentFormError] when PaymentFormLoadSupportedCountries event is added but throws getting the list of countries',
        build: () => paymentFormBloc,
        act: (bloc) {
          when(() => mockTurbo.getSupportedCountries())
              .thenThrow((_) => Exception());
          bloc.add(PaymentFormLoadSupportedCountries());
        },
        expect: () => [
          isA<PaymentFormLoading>(),
          isA<PaymentFormError>(),
        ],
      );
    });
  });

  group('promo code', () {
    final validPromoCodes = {
      'BANANA': 0.1,
      'MANZANA': 0.2,
      'FRUTILLA': 1.0,
    };
    late PriceEstimate initialPriceEstimate;
    // PriceEstimate? estimateInState;

    setUp(() {
      mockTurbo = MockTurbo();
      initialPriceEstimate = PriceEstimate(
        estimate: PriceForFiat(
          winc: BigInt.from(10),
          adjustments: const [],
          actualPaymentAmount: null,
          quotedPaymentAmount: null,
        ),
        priceInCurrency: 10,
        estimatedStorage: 1,
      );

      when(() => mockTurbo.maxQuoteExpirationDate).thenAnswer(
          (invocation) => DateTime.now().add(const Duration(days: 1)));
      paymentFormBloc = PaymentFormBloc(
        mockTurbo,
        initialPriceEstimate,
        mockExpirationTimeInSeconds: (DateTime d) => 1234,
      );
    });

    blocTest<PaymentFormBloc, PaymentFormState>(
      'is accordingly being updated depending on the promo code entered',
      build: () {
        when(() => mockTurbo.refreshPriceEstimate(
            promoCode: any(named: 'promoCode'))).thenAnswer((_) async {
          final promoCode = _.namedArguments[#promoCode] as String?;
          final isValidPromoCode = validPromoCodes.containsKey(promoCode);
          final discountFactor = validPromoCodes[promoCode];

          if (promoCode == 'NETWORK ERROR') {
            throw Exception();
          }

          if (isValidPromoCode) {
            final quotedAmount = (initialPriceEstimate.priceInCurrency).floor();
            final magnitude = (100 - (100 * discountFactor!)) / 100;
            final adjustmentAmount = (quotedAmount * discountFactor).floor();
            final actualAmount = quotedAmount - adjustmentAmount;

            final estimate = PriceForFiat(
              winc: BigInt.from(10),
              adjustments: [
                Adjustment(
                  name: 'Promo code',
                  description: 'Promo code',
                  operatorMagnitude: magnitude,
                  operator: 'multiply',
                  adjustmentAmount: adjustmentAmount,
                  maxDiscount: null,
                )
              ],
              actualPaymentAmount: actualAmount,
              quotedPaymentAmount: quotedAmount,
            );

            final priceEstimate = PriceEstimate(
              estimate: estimate,
              priceInCurrency: 10,
              estimatedStorage: 1,
            );

            // estimateInState = priceEstimate;

            return priceEstimate;
          } else {
            throw PaymentServiceInvalidPromoCode(promoCode: promoCode);
          }
        });

        return paymentFormBloc;
      },
      seed: () {
        return PaymentFormLoaded(
          initialPriceEstimate,
          DateTime.now()
              .add(const Duration(days: 1))
              .difference(DateTime.now())
              .inSeconds,
          const [],
        );
      },
      act: (bloc) async {
        bloc.add(const PaymentFormUpdatePromoCode('BANANA'));
        bloc.add(const PaymentFormUpdatePromoCode(''));
        bloc.add(const PaymentFormUpdatePromoCode('NETWORK ERROR'));
        bloc.add(const PaymentFormUpdatePromoCode(''));
        bloc.add(const PaymentFormUpdatePromoCode('MANZANA'));
      },
      expect: () => [
        // Fetching for BANANA
        PaymentFormLoaded(
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
          1234,
          const [],
          isPromoCodeInvalid: false,
          isFetchingPromoCode: true,
          errorFetchingPromoCode: false,
        ),
        // Valid result for BANANA
        PaymentFormLoaded(
          PriceEstimate(
            estimate: PriceForFiat(
              winc: BigInt.from(10),
              adjustments: const [
                Adjustment(
                  name: 'Promo code',
                  description: 'Promo code',
                  operatorMagnitude: 0.9,
                  operator: 'multiply',
                  adjustmentAmount: 1,
                  maxDiscount: null,
                )
              ],
              actualPaymentAmount: 9,
              quotedPaymentAmount: 10,
            ),
            priceInCurrency: 10,
            estimatedStorage: 1,
          ),
          1234,
          const [],
          isPromoCodeInvalid: false,
          isFetchingPromoCode: false,
          errorFetchingPromoCode: false,
        ),

        // Fetching for empty
        PaymentFormLoaded(
          PriceEstimate(
            estimate: PriceForFiat(
              winc: BigInt.from(10),
              adjustments: const [
                Adjustment(
                  name: 'Promo code',
                  description: 'Promo code',
                  operatorMagnitude: 0.9,
                  operator: 'multiply',
                  adjustmentAmount: 1,
                  maxDiscount: null,
                )
              ],
              actualPaymentAmount: 9,
              quotedPaymentAmount: 10,
            ),
            priceInCurrency: 10,
            estimatedStorage: 1,
          ),
          1234,
          const [],
          isPromoCodeInvalid: false,
          isFetchingPromoCode: true,
          errorFetchingPromoCode: false,
        ),
        // Invalid result for empty
        PaymentFormLoaded(
          PriceEstimate(
            estimate: PriceForFiat(
              winc: BigInt.from(10),
              adjustments: const [
                Adjustment(
                  name: 'Promo code',
                  description: 'Promo code',
                  operatorMagnitude: 0.9,
                  operator: 'multiply',
                  adjustmentAmount: 1,
                  maxDiscount: null,
                )
              ],
              actualPaymentAmount: 9,
              quotedPaymentAmount: 10,
            ),
            priceInCurrency: 10,
            estimatedStorage: 1,
          ),
          1234,
          const [],
          isPromoCodeInvalid: true,
          isFetchingPromoCode: false,
          errorFetchingPromoCode: false,
        ),

        // Fetching for ERROR
        PaymentFormLoaded(
          PriceEstimate(
            estimate: PriceForFiat(
              winc: BigInt.from(10),
              adjustments: const [
                Adjustment(
                  name: 'Promo code',
                  description: 'Promo code',
                  operatorMagnitude: 0.9,
                  operator: 'multiply',
                  adjustmentAmount: 1,
                  maxDiscount: null,
                )
              ],
              actualPaymentAmount: 9,
              quotedPaymentAmount: 10,
            ),
            priceInCurrency: 10,
            estimatedStorage: 1,
          ),
          1234,
          const [],
          isPromoCodeInvalid: false,
          isFetchingPromoCode: true,
          errorFetchingPromoCode: false,
        ),
        // Error while fetching for ERROR
        PaymentFormLoaded(
          PriceEstimate(
            estimate: PriceForFiat(
              winc: BigInt.from(10),
              adjustments: const [
                Adjustment(
                  name: 'Promo code',
                  description: 'Promo code',
                  operatorMagnitude: 0.9,
                  operator: 'multiply',
                  adjustmentAmount: 1,
                  maxDiscount: null,
                )
              ],
              actualPaymentAmount: 9,
              quotedPaymentAmount: 10,
            ),
            priceInCurrency: 10,
            estimatedStorage: 1,
          ),
          1234,
          const [],
          isPromoCodeInvalid: false,
          isFetchingPromoCode: false,
          errorFetchingPromoCode: true,
        ),

        // Fetching for empty
        PaymentFormLoaded(
          PriceEstimate(
            estimate: PriceForFiat(
              winc: BigInt.from(10),
              adjustments: const [
                Adjustment(
                  name: 'Promo code',
                  description: 'Promo code',
                  operatorMagnitude: 0.9,
                  operator: 'multiply',
                  adjustmentAmount: 1,
                  maxDiscount: null,
                )
              ],
              actualPaymentAmount: 9,
              quotedPaymentAmount: 10,
            ),
            priceInCurrency: 10,
            estimatedStorage: 1,
          ),
          1234,
          const [],
          isPromoCodeInvalid: false,
          isFetchingPromoCode: true,
          errorFetchingPromoCode: false,
        ),
        // Invalid result for empty
        PaymentFormLoaded(
          PriceEstimate(
            estimate: PriceForFiat(
              winc: BigInt.from(10),
              adjustments: const [
                Adjustment(
                  name: 'Promo code',
                  description: 'Promo code',
                  operatorMagnitude: 0.9,
                  operator: 'multiply',
                  adjustmentAmount: 1,
                  maxDiscount: null,
                )
              ],
              actualPaymentAmount: 9,
              quotedPaymentAmount: 10,
            ),
            priceInCurrency: 10,
            estimatedStorage: 1,
          ),
          1234,
          const [],
          isPromoCodeInvalid: true,
          isFetchingPromoCode: false,
          errorFetchingPromoCode: false,
        ),

        // Fetching for MANZANA
        PaymentFormLoaded(
          PriceEstimate(
            estimate: PriceForFiat(
              winc: BigInt.from(10),
              adjustments: const [
                Adjustment(
                  name: 'Promo code',
                  description: 'Promo code',
                  operatorMagnitude: 0.9,
                  operator: 'multiply',
                  adjustmentAmount: 1,
                  maxDiscount: null,
                )
              ],
              actualPaymentAmount: 9,
              quotedPaymentAmount: 10,
            ),
            priceInCurrency: 10,
            estimatedStorage: 1,
          ),
          1234,
          const [],
          isPromoCodeInvalid: false,
          isFetchingPromoCode: true,
          errorFetchingPromoCode: false,
        ),
        // Valid result for MANZANA
        PaymentFormLoaded(
          PriceEstimate(
            estimate: PriceForFiat(
              winc: BigInt.from(10),
              adjustments: const [
                Adjustment(
                  name: 'Promo code',
                  description: 'Promo code',
                  operatorMagnitude: 0.8,
                  operator: 'multiply',
                  adjustmentAmount: 2,
                  maxDiscount: null,
                )
              ],
              actualPaymentAmount: 8,
              quotedPaymentAmount: 10,
            ),
            priceInCurrency: 10,
            estimatedStorage: 1,
          ),
          1234,
          const [],
          isPromoCodeInvalid: false,
          isFetchingPromoCode: false,
          errorFetchingPromoCode: false,
        ),
      ],
    );

    // has reached max discount
    blocTest<PaymentFormBloc, PaymentFormState>(
      'hasReachedMaximumDiscount is true when the discount reaches the maximum',
      build: () {
        when(() => mockTurbo.refreshPriceEstimate(
            promoCode: any(named: 'promoCode'))).thenAnswer((_) async {
          final promoCode = _.namedArguments[#promoCode] as String?;
          final isValidPromoCode = validPromoCodes.containsKey(promoCode);
          final discountFactor = validPromoCodes[promoCode];
          const maxDiscount = 5;

          if (isValidPromoCode) {
            final quotedAmount = (initialPriceEstimate.priceInCurrency).floor();
            final magnitude = (100 - (100 * discountFactor!)) / 100;
            int adjustmentAmount = (quotedAmount * discountFactor).floor();

            // Here we simulate that the discount has reached the maximum
            if (adjustmentAmount > maxDiscount) {
              adjustmentAmount = maxDiscount;
            }
            final actualAmount = quotedAmount - adjustmentAmount;

            final estimate = PriceForFiat(
              winc: BigInt.from(10),
              adjustments: [
                Adjustment(
                  name: 'Promo code',
                  description: 'Promo code',
                  operatorMagnitude: magnitude,
                  operator: 'multiply',
                  adjustmentAmount: adjustmentAmount,
                  maxDiscount: maxDiscount,
                )
              ],
              actualPaymentAmount: actualAmount,
              quotedPaymentAmount: quotedAmount,
            );

            final priceEstimate = PriceEstimate(
              estimate: estimate,
              priceInCurrency: 10,
              estimatedStorage: 1,
            );

            return priceEstimate;
          } else {
            throw PaymentServiceInvalidPromoCode(promoCode: promoCode);
          }
        });

        return paymentFormBloc;
      },
      seed: () {
        return PaymentFormLoaded(
          initialPriceEstimate,
          DateTime.now()
              .add(const Duration(days: 1))
              .difference(DateTime.now())
              .inSeconds,
          const [],
        );
      },
      act: (bloc) async {
        bloc.add(const PaymentFormUpdatePromoCode('FRUTILLA'));
      },
      expect: () => [
        // Fetching for FRUTILLA
        PaymentFormLoaded(
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
          1234,
          const [],
          isPromoCodeInvalid: false,
          isFetchingPromoCode: true,
          errorFetchingPromoCode: false,
        ),
        // Valid result for FRUTILLA
        PaymentFormLoaded(
          PriceEstimate(
            estimate: PriceForFiat(
              winc: BigInt.from(10),
              adjustments: const [
                Adjustment(
                  name: 'Promo code',
                  description: 'Promo code',
                  operatorMagnitude: 0,
                  operator: 'multiply',
                  adjustmentAmount: 5,
                  maxDiscount: 5,
                )
              ],
              actualPaymentAmount: 5,
              quotedPaymentAmount: 10,
            ),
            priceInCurrency: 10,
            estimatedStorage: 1,
          ),
          1234,
          const [],
          isPromoCodeInvalid: false,
          isFetchingPromoCode: false,
          errorFetchingPromoCode: false,
        ),
      ],
    );
  });
}
