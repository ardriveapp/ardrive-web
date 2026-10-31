import 'package:ardrive/turbo/services/crypto_price_service.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/blocs/unified_topup/unified_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/file_size_units.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockTurbo extends Mock implements Turbo {}

class MockCryptoPriceService extends Mock implements CryptoPriceService {}

void main() {
  setUpAll(() {
    registerFallbackValue(FileSizeUnit.bytes);
    registerFallbackValue(BigInt.zero);
  });

  test(
      'storage estimate is shown in the right magnitude when the display unit '
      'is not GiB', () async {
    final turbo = MockTurbo();
    when(() => turbo.onPriceEstimateChanged)
        .thenAnswer((_) => const Stream.empty());
    when(() => turbo.getBalance()).thenAnswer((_) async => BigInt.zero);
    when(() => turbo.promoCode).thenReturn(null);
    when(() => turbo.computeStorageEstimateForCredits(
          credits: any(named: 'credits'),
          outputDataUnit: any(named: 'outputDataUnit'),
        )).thenAnswer((_) async => 0);
    // Like the real Turbo, the estimate comes back in the requested unit:
    // half a GiB is 512 MiB.
    when(() => turbo.computePriceEstimate(
          currentAmount: any(named: 'currentAmount'),
          currentCurrency: any(named: 'currentCurrency'),
          currentDataUnit: any(named: 'currentDataUnit'),
          promoCode: any(named: 'promoCode'),
        )).thenAnswer((i) async {
      final unit = i.namedArguments[#currentDataUnit] as FileSizeUnit;
      return PriceEstimate(
        estimate: PriceForFiat(
          winc: BigInt.from(1000),
          actualPaymentAmount: 1000,
          quotedPaymentAmount: 1000,
          adjustments: const [],
        ),
        priceInCurrency: 10,
        estimatedStorage: unit == FileSizeUnit.megabytes ? 512 : 0.5,
      );
    });

    final bloc = UnifiedTopupBloc(
      turbo: turbo,
      priceService: MockCryptoPriceService(),
    );
    addTearDown(bloc.close);

    bloc.add(const UnifiedTopupStarted());
    await bloc.stream.firstWhere((s) => s is UnifiedTopupLoaded);
    bloc.add(const UnifiedTopupDataUnitChanged(FileSizeUnit.megabytes));
    bloc.add(const UnifiedTopupAmountSelected(10));
    await bloc.stream.firstWhere(
      (s) => s is UnifiedTopupLoaded && !s.isLoadingQuote && s.fiatAmount == 10,
    );

    final state = bloc.state as UnifiedTopupLoaded;
    expect(state.estimatedStorage, '512.0 MB');
  });

  test('a rejected promo code is reported on the promo field, not the page',
      () async {
    final turbo = MockTurbo();
    when(() => turbo.onPriceEstimateChanged)
        .thenAnswer((_) => const Stream.empty());
    when(() => turbo.getBalance()).thenAnswer((_) async => BigInt.zero);
    when(() => turbo.promoCode).thenReturn(null);
    when(() => turbo.computeStorageEstimateForCredits(
          credits: any(named: 'credits'),
          outputDataUnit: any(named: 'outputDataUnit'),
        )).thenAnswer((_) async => 0);
    when(() => turbo.computePriceEstimate(
          currentAmount: any(named: 'currentAmount'),
          currentCurrency: any(named: 'currentCurrency'),
          currentDataUnit: any(named: 'currentDataUnit'),
          promoCode: any(named: 'promoCode'),
        )).thenAnswer((i) async {
      if (i.namedArguments[#promoCode] == 'NOPE') throw Exception('invalid');
      return PriceEstimate(
        estimate: PriceForFiat(
          winc: BigInt.from(1000),
          actualPaymentAmount: 1000,
          quotedPaymentAmount: 1000,
          adjustments: const [],
        ),
        priceInCurrency: 10,
        estimatedStorage: 0.5,
      );
    });

    final bloc = UnifiedTopupBloc(
      turbo: turbo,
      priceService: MockCryptoPriceService(),
    );
    addTearDown(bloc.close);

    bloc.add(const UnifiedTopupStarted());
    await bloc.stream.firstWhere((s) => s is UnifiedTopupLoaded);
    bloc.add(const UnifiedTopupAmountSelected(10));
    await bloc.stream.firstWhere(
      (s) => s is UnifiedTopupLoaded && !s.isLoadingQuote && s.fiatAmount == 10,
    );
    bloc.add(const UnifiedTopupPromoCodeSubmitted('NOPE'));
    await bloc.stream.firstWhere(
      (s) => s is UnifiedTopupLoaded && s.promoCodeError != null,
    );

    final state = bloc.state as UnifiedTopupLoaded;
    expect(state.promoCodeError, 'Invalid promo code');
    expect(state.errorMessage, isNull);
    expect(state.promoCode, isNull);
    // The code was dropped, so the purchase goes on at the full price.
    expect(state.canContinue, isTrue);

    // A new amount is a new quote: the old rejection no longer applies.
    bloc.add(const UnifiedTopupAmountSelected(20));
    await bloc.stream.firstWhere(
      (s) => s is UnifiedTopupLoaded && s.fiatAmount == 20,
    );
    expect((bloc.state as UnifiedTopupLoaded).promoCodeError, isNull);
  });
}
