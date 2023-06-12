import 'package:ardrive/turbo/topup/blocs/topup_estimation_bloc.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/file_size_units.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockTurbo extends Mock implements Turbo {}

void main() {
  late MockTurbo mockTurbo;
  late TurboTopUpEstimationBloc topUpBloc;

  setUp(() {
    mockTurbo = MockTurbo();
    topUpBloc = TurboTopUpEstimationBloc(turbo: mockTurbo);
    registerFallbackValue(FileSizeUnit.gigabytes);
  });

  tearDown(() {
    topUpBloc.close();
  });

  group('TurboTopUpEstimationBloc', () {
    group('LoadInitialData', () {
      blocTest<TurboTopUpEstimationBloc, TopupEstimationState>(
        'Emits [EstimationLoaded] with correct data when LoadInitialData is added',
        build: () => TurboTopUpEstimationBloc(turbo: mockTurbo),
        act: (bloc) async {
          final mockPriceEstimate = PriceEstimate(
              credits: BigInt.from(10),
              priceInCurrency: 10,
              estimatedStorage: 1);

          when(() => mockTurbo.getBalance())
              .thenAnswer((_) async => BigInt.from(10));
          when(() => mockTurbo.computePriceEstimateAndUpdate(
                currentAmount: 0,
                currentCurrency: 'usd',
                currentDataUnit: FileSizeUnit.gigabytes,
              )).thenAnswer((_) async => mockPriceEstimate);
          when(() => mockTurbo.computeStorageEstimateForCredits(
                credits: BigInt.from(10),
                outputDataUnit: FileSizeUnit.gigabytes,
              )).thenAnswer((_) async => 1);

          bloc.add(LoadInitialData());
        },
        expect: () => [
          EstimationLoaded(
            balance: BigInt.from(10),
            estimatedStorageForBalance: '1.00',
            selectedAmount: 10,
            creditsForSelectedAmount: BigInt.from(10),
            estimatedStorageForSelectedAmount: '1.00',
            currencyUnit: 'usd',
            dataUnit: FileSizeUnit.gigabytes,
          ),
        ],
      );

      blocTest('Emits [EstimationError] if getBalance throws',
          build: () {
            when(() => mockTurbo.getBalance()).thenThrow(Exception());

            return TurboTopUpEstimationBloc(turbo: mockTurbo);
          },
          act: (bloc) async {
            bloc.add(LoadInitialData());
          },
          expect: () => [
                EstimationError(),
              ]);
      blocTest(
          'Emits [EstimationError] if getBalance doesnt throw but computePriceEstimateAndUpdate do',
          build: () {
            return TurboTopUpEstimationBloc(turbo: mockTurbo);
          },
          act: (bloc) async {
            bloc.add(LoadInitialData());
          },
          setUp: () {
            when(() => mockTurbo.getBalance())
                .thenAnswer((_) async => BigInt.from(10));
            when(() => mockTurbo.computePriceEstimateAndUpdate(
                    currentAmount: any(named: 'currentAmount'),
                    currentCurrency: any(named: 'currentCurrency'),
                    currentDataUnit: any(named: 'currentDataUnit')))
                .thenThrow(Exception());
          },
          expect: () => [
                EstimationError(),
              ]);
      blocTest(
          'Emits [EstimationError] if getBalance and computePriceEstimateAndUpdate doent throw but computeStorageEstimateForCredits do',
          build: () {
            return TurboTopUpEstimationBloc(turbo: mockTurbo);
          },
          act: (bloc) async {
            bloc.add(LoadInitialData());
          },
          setUp: () {
            final mockPriceEstimate = PriceEstimate(
                credits: BigInt.from(10),
                priceInCurrency: 10,
                estimatedStorage: 1);

            when(() => mockTurbo.getBalance())
                .thenAnswer((_) async => BigInt.from(10));
            when(() => mockTurbo.computePriceEstimateAndUpdate(
                  currentAmount: 0,
                  currentCurrency: 'usd',
                  currentDataUnit: FileSizeUnit.gigabytes,
                )).thenAnswer((_) async => mockPriceEstimate);
            when(() => mockTurbo.computeStorageEstimateForCredits(
                  credits: BigInt.from(10),
                  outputDataUnit: FileSizeUnit.gigabytes,
                )).thenThrow(Exception());
          },
          expect: () => [
                EstimationError(),
              ]);
    });
  });

  group('ChangeCurrency', () {
    blocTest<TurboTopUpEstimationBloc, TopupEstimationState>(
      'Emits [EstimationLoaded] with updated currency when ChangeCurrency is added',
      build: () => TurboTopUpEstimationBloc(turbo: mockTurbo),
      act: (bloc) async {
        bloc.add(LoadInitialData());
        bloc.add(const CurrencyUnitChanged('eur'));
      },
      setUp: () {
        final mockPriceEstimate = PriceEstimate(
            credits: BigInt.from(10), priceInCurrency: 10, estimatedStorage: 1);

        when(() => mockTurbo.getBalance())
            .thenAnswer((_) async => BigInt.from(10));
        when(() => mockTurbo.computePriceEstimateAndUpdate(
              currentAmount: 0,
              currentCurrency: 'usd',
              currentDataUnit: FileSizeUnit.gigabytes,
            )).thenAnswer((_) async => mockPriceEstimate);
        when(() => mockTurbo.computePriceEstimateAndUpdate(
              currentAmount: 0,
              currentCurrency: 'eur',
              currentDataUnit: FileSizeUnit.gigabytes,
            )).thenAnswer((_) async => mockPriceEstimate);
        when(() => mockTurbo.computeStorageEstimateForCredits(
              credits: BigInt.from(10),
              outputDataUnit: FileSizeUnit.gigabytes,
            )).thenAnswer((_) async => 1);
      },
      expect: () => [
        // first loads with usd
        EstimationLoaded(
          balance: BigInt.from(10),
          estimatedStorageForBalance: '1.00',
          selectedAmount: 10,
          creditsForSelectedAmount: BigInt.from(10),
          estimatedStorageForSelectedAmount: '1.00',
          currencyUnit: 'usd',
          dataUnit: FileSizeUnit.gigabytes,
        ),
        // then emit eur
        EstimationLoaded(
          balance: BigInt.from(10),
          estimatedStorageForBalance: '1.00',
          selectedAmount: 10,
          creditsForSelectedAmount: BigInt.from(10),
          estimatedStorageForSelectedAmount: '1.00',
          currencyUnit: 'eur',
          dataUnit: FileSizeUnit.gigabytes,
        ),
      ],
    );
  });

  group('DataUnitChanged', () {
    blocTest<TurboTopUpEstimationBloc, TopupEstimationState>(
      'Emits [EstimationLoaded] with updated currency when DataUnitChanged is added',
      build: () => TurboTopUpEstimationBloc(turbo: mockTurbo),
      act: (bloc) async {
        bloc.add(LoadInitialData());
        bloc.add(const DataUnitChanged(FileSizeUnit.kilobytes));
      },
      setUp: () {
        final mockPriceEstimate = PriceEstimate(
            credits: BigInt.from(10), priceInCurrency: 10, estimatedStorage: 1);

        when(() => mockTurbo.getBalance())
            .thenAnswer((_) async => BigInt.from(10));
        // GiB
        when(() => mockTurbo.computePriceEstimateAndUpdate(
              currentAmount: 0,
              currentCurrency: 'usd',
              currentDataUnit: FileSizeUnit.gigabytes,
            )).thenAnswer((_) async => mockPriceEstimate);
        when(() => mockTurbo.computeStorageEstimateForCredits(
              credits: BigInt.from(10),
              outputDataUnit: FileSizeUnit.gigabytes,
            )).thenAnswer((_) async => 1);

        // KiB
        when(() => mockTurbo.computePriceEstimateAndUpdate(
              currentAmount: 0,
              currentCurrency: 'usd',
              currentDataUnit: FileSizeUnit.kilobytes,
            )).thenAnswer((_) async => mockPriceEstimate);

        when(() => mockTurbo.computeStorageEstimateForCredits(
              credits: BigInt.from(10),
              outputDataUnit: FileSizeUnit.kilobytes,
            )).thenAnswer((_) async => 1);
      },
      expect: () => [
        // first loads with usd
        EstimationLoaded(
          balance: BigInt.from(10),
          estimatedStorageForBalance: '1.00',
          selectedAmount: 10,
          creditsForSelectedAmount: BigInt.from(10),
          estimatedStorageForSelectedAmount: '1.00',
          currencyUnit: 'usd',
          dataUnit: FileSizeUnit.gigabytes,
        ),
        // then emit eur
        EstimationLoaded(
          balance: BigInt.from(10),
          estimatedStorageForBalance: '1.00',
          selectedAmount: 10,
          creditsForSelectedAmount: BigInt.from(10),
          estimatedStorageForSelectedAmount: '1.00',
          currencyUnit: 'usd',
          dataUnit: FileSizeUnit.kilobytes,
        ),
      ],
    );
  });

  group('FiatAmountSelected', () {
    blocTest<TurboTopUpEstimationBloc, TopupEstimationState>(
      'Emits [EstimationLoaded] with updated currency when FiatAmountSelected is added',
      build: () => TurboTopUpEstimationBloc(turbo: mockTurbo),
      act: (bloc) async {
        bloc.add(LoadInitialData());
        bloc.add(const FiatAmountSelected(100));
      },
      setUp: () {
        final mockPriceEstimate = PriceEstimate(
            credits: BigInt.from(10), priceInCurrency: 0, estimatedStorage: 1);
        final mockPriceEstimate100 = PriceEstimate(
            credits: BigInt.from(10),
            priceInCurrency: 100,
            estimatedStorage: 1);

        when(() => mockTurbo.getBalance())
            .thenAnswer((_) async => BigInt.from(10));
        when(() => mockTurbo.computePriceEstimateAndUpdate(
              currentAmount: 0,
              currentCurrency: 'usd',
              currentDataUnit: FileSizeUnit.gigabytes,
            )).thenAnswer((_) async => mockPriceEstimate);
        when(() => mockTurbo.computeStorageEstimateForCredits(
              credits: BigInt.from(10),
              outputDataUnit: FileSizeUnit.gigabytes,
            )).thenAnswer((_) async => 1);

        // second call with 100 amount
        when(() => mockTurbo.computePriceEstimateAndUpdate(
              currentAmount: 100,
              currentCurrency: 'usd',
              currentDataUnit: FileSizeUnit.gigabytes,
            )).thenAnswer((_) async => mockPriceEstimate100);
        when(() => mockTurbo.computeStorageEstimateForCredits(
              credits: BigInt.from(10),
              outputDataUnit: FileSizeUnit.gigabytes,
            )).thenAnswer((_) async => 1);
      },
      expect: () => [
        // start with 0
        EstimationLoaded(
          balance: BigInt.from(10),
          estimatedStorageForBalance: '1.00',
          selectedAmount: 0,
          creditsForSelectedAmount: BigInt.from(10),
          estimatedStorageForSelectedAmount: '1.00',
          currencyUnit: 'usd',
          dataUnit: FileSizeUnit.gigabytes,
        ),
        // 100
        EstimationLoaded(
          balance: BigInt.from(10),
          estimatedStorageForBalance: '1.00',
          selectedAmount: 100,
          creditsForSelectedAmount: BigInt.from(10),
          estimatedStorageForSelectedAmount: '1.00',
          currencyUnit: 'usd',
          dataUnit: FileSizeUnit.gigabytes,
        ),
      ],
    );
  });
}
