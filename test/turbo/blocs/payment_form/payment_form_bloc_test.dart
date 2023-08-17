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
          credits: BigInt.from(10), priceInCurrency: 10, estimatedStorage: 1);
      when(() => mockTurbo.maxQuoteExpirationDate).thenAnswer(
          (invocation) => DateTime.now().add(const Duration(days: 1)));
      paymentFormBloc = PaymentFormBloc(mockTurbo, initialPriceEstimate);
    });

    group('PaymentFormUpdateQuote', () {
      setUp(() {
        mockTurbo = MockTurbo();
        final initialPriceEstimate = PriceEstimate(
            credits: BigInt.from(10), priceInCurrency: 10, estimatedStorage: 1);
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
            DateTime.now()
                .add(const Duration(days: 1))
                .difference(DateTime.now())
                .inSeconds,
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
}
