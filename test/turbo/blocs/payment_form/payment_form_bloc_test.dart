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

  group('PaymentFormBloc', () {
    setUp(() {
      mockTurbo = MockTurbo();
      final initialPriceEstimate = PriceEstimate(
          credits: BigInt.from(10), priceInCurrency: 10, estimatedStorage: 1);
      when(() => mockTurbo.maxQuoteExpirationDate).thenAnswer(
          (invocation) => DateTime.now().add(const Duration(days: 1)));
      paymentFormBloc = PaymentFormBloc(mockTurbo, initialPriceEstimate);
    });

    group('PaymentFormPrePopulateFields', () {
      blocTest<PaymentFormBloc, PaymentFormState>(
        'Emits [PaymentFormPopulatingFieldsForTesting] when PaymentFormPrePopulateFields is added',
        build: () => paymentFormBloc,
        act: (bloc) async {
          bloc.add(PaymentFormPrePopulateFields());
        },
        expect: () => [
          isA<PaymentFormPopulatingFieldsForTesting>(),
        ],
      );
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
          return paymentFormBloc;
        },
        act: (bloc) async {
          bloc.add(PaymentFormUpdateQuote());
        },
        expect: () => [
          isA<PaymentFormLoadingQuote>(),
          isA<PaymentFormQuoteLoaded>(),
        ],
      );

      blocTest<PaymentFormBloc, PaymentFormState>(
        'Emits [PaymentFormLoadingQuote], then remains unchanged when PaymentFormUpdateQuote is added and refreshPriceEstimate throws',
        build: () {
          when(() => mockTurbo.refreshPriceEstimate()).thenThrow(Exception());
          return paymentFormBloc;
        },
        act: (bloc) async {
          bloc.add(PaymentFormUpdateQuote());
        },
        expect: () => [
          isA<PaymentFormLoadingQuote>(),
          isA<PaymentFormQuoteLoadFailure>(),
        ],
      );
    });
  });
}
