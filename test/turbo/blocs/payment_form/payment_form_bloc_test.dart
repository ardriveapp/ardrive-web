import 'package:ardrive/turbo/topup/blocs/payment_form/payment_form_bloc.dart';
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
        credits: BigInt.from(10),
        priceInCurrency: 10,
        estimatedStorage: 1,
        promoDiscountFactor: 0,
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
          credits: BigInt.from(10),
          priceInCurrency: 10,
          estimatedStorage: 1,
          promoDiscountFactor: 0,
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
              credits: BigInt.from(15),
              priceInCurrency: 15,
              estimatedStorage: 1.5,
              promoDiscountFactor: 0,
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
    };
    const errorPromoCode = 'ERROR';

    setUp(() {
      mockTurbo = MockTurbo();
      final initialPriceEstimate = PriceEstimate(
        credits: BigInt.from(10),
        priceInCurrency: 10,
        estimatedStorage: 1,
        promoDiscountFactor: 0,
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
        when(() => mockTurbo.getPromoDiscountFactor(any()))
            .thenAnswer((invocation) async {
          final promoCode = invocation.positionalArguments[0] as String;
          if (validPromoCodes.containsKey(promoCode)) {
            return validPromoCodes[promoCode];
          } else {
            // invalid promo code
            return 0.0;
          }
        });

        when(() => mockTurbo.getPromoDiscountFactor(errorPromoCode))
            .thenThrow(Exception());

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
        bloc.add(const PaymentFormUpdatePromoCode(errorPromoCode));
        bloc.add(const PaymentFormUpdatePromoCode('MANZANA'));
      },
      expect: () => [
        PaymentFormLoaded(
          initialPriceEstimate,
          1234,
          const [],
          promoDiscountFactor: 0,
          isPromoCodeInvalid: false,
          isFetchingPromoCode: true,
          errorFetchingPromoCode: false,
        ),
        PaymentFormLoaded(
          initialPriceEstimate,
          1234,
          const [],
          promoDiscountFactor: 0.1,
          isPromoCodeInvalid: false,
          isFetchingPromoCode: false,
          errorFetchingPromoCode: false,
        ),
        PaymentFormLoaded(
          initialPriceEstimate,
          1234,
          const [],
          promoDiscountFactor: 0,
          isPromoCodeInvalid: false,
          isFetchingPromoCode: true,
          errorFetchingPromoCode: false,
        ),
        PaymentFormLoaded(
          initialPriceEstimate,
          1234,
          const [],
          promoDiscountFactor: 0,
          isPromoCodeInvalid: false,
          isFetchingPromoCode: false,
          errorFetchingPromoCode: true,
        ),
        PaymentFormLoaded(
          initialPriceEstimate,
          1234,
          const [],
          promoDiscountFactor: 0,
          isPromoCodeInvalid: false,
          isFetchingPromoCode: true,
          errorFetchingPromoCode: false,
        ),
        PaymentFormLoaded(
          initialPriceEstimate,
          1234,
          const [],
          promoDiscountFactor: 0.2,
          isPromoCodeInvalid: false,
          isFetchingPromoCode: false,
          errorFetchingPromoCode: false,
        ),
      ],
    );
  });
}
