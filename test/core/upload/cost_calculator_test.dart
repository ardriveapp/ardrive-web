import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/types/winston.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

// We start by creating mocks for the services that will be used
class MockArweaveService extends Mock implements ArweaveService {}

class MockPstService extends Mock implements PstService {}

class MockTurboCostCalculator extends Mock implements TurboCostCalculator {}

class MockTurboPriceEstimator extends Mock implements TurboPriceEstimator {}

class MockArCostToUsd extends Mock implements ConvertArToUSD {}

void main() {
  setUpAll(() {
    registerFallbackValue(
        BigInt.zero); // Necessary to allow BigInt as parameter in when().
  });

  group('UploadCostEstimateCalculatorForAR', () {
    late ArweaveService arweaveService;
    late PstService pstService;
    late UploadCostEstimateCalculatorForAR uploadCostEstimateCalculator;
    late ConvertArToUSD arCostToUsd;

    setUp(() {
      arweaveService = MockArweaveService();
      pstService = MockPstService();
      arCostToUsd = MockArCostToUsd();

      uploadCostEstimateCalculator = UploadCostEstimateCalculatorForAR(
        arweaveService: arweaveService,
        pstService: pstService,
        arCostToUsd: arCostToUsd,
      );
    });

    test('calculateCost should correctly call getPrice and getPSTFee',
        () async {
      when(() => arweaveService.getPrice(byteSize: any(named: 'byteSize')))
          .thenAnswer((_) => Future.value(BigInt.from(10)));
      when(() => pstService.getPSTFee(any()))
          .thenAnswer((_) => Future.value(Winston(BigInt.from(2))));
      when(() => arCostToUsd.convertForUSD(0.000000000012))
          .thenAnswer((_) => Future.value(10.0));

      final result =
          await uploadCostEstimateCalculator.calculateCost(totalSize: 100);

      verify(() => arweaveService.getPrice(byteSize: 100)).called(1);
      verify(() => pstService.getPSTFee(BigInt.from(10))).called(1);
      verify(() => arCostToUsd.convertForUSD(0.000000000012)).called(1);
      expect(
        result,
        UploadCostEstimate(
          pstFee: BigInt.from(2),
          totalCost: BigInt.from(12),
          totalSize: 100,
          usdUploadCost: 10,
        ),
      );
    });

    test('calculateCost should correctly call getPrice and getPSTFee',
        () async {
      final price = BigInt.from(100000000000);

      final fee = Winston(BigInt.from(2));

      when(() => arweaveService.getPrice(byteSize: any(named: 'byteSize')))
          .thenAnswer((_) => Future.value(price));
      when(() => pstService.getPSTFee(any()))
          .thenAnswer((_) => Future.value(fee));
      when(() => arCostToUsd.convertForUSD(0.100000000002))
          .thenAnswer((_) => Future.value(10.0));

      final result =
          await uploadCostEstimateCalculator.calculateCost(totalSize: 100);

      verify(() => arweaveService.getPrice(byteSize: 100)).called(1);
      verify(() => pstService.getPSTFee(price)).called(1);
      verify(() => arCostToUsd.convertForUSD(0.100000000002)).called(1);
      expect(
        result,
        UploadCostEstimate(
          pstFee: fee.value,
          totalCost: fee.value + price,
          totalSize: 100,
          usdUploadCost: 10,
        ),
      );
    });
  });

  group('TurboUploadCostCalculator', () {
    late TurboCostCalculator turboCostCalculator;
    late TurboPriceEstimator priceEstimator;
    late PstService pstService;
    late TurboUploadCostCalculator turboUploadCostCalculator;

    setUp(() {
      turboCostCalculator = MockTurboCostCalculator();
      priceEstimator = MockTurboPriceEstimator();
      pstService = MockPstService();
      turboUploadCostCalculator = TurboUploadCostCalculator(
        turboCostCalculator: turboCostCalculator,
        priceEstimator: priceEstimator,
      );
    });

    test(
        'calculateCost should correctly call getCostForBytes, getPSTFee and convertCreditsForUSD',
        () async {
      when(() => turboCostCalculator.getCostForBytes(
              byteSize: any(named: 'byteSize')))
          .thenAnswer((_) => Future.value(BigInt.from(10)));
      when(() => priceEstimator.convertForUSD(BigInt.from(10)))
          .thenAnswer((_) => Future.value(10.0));

      final result =
          await turboUploadCostCalculator.calculateCost(totalSize: 100);

      verify(() => turboCostCalculator.getCostForBytes(byteSize: 100))
          .called(1);
      verify(() => priceEstimator.convertForUSD(BigInt.from(10))).called(1);
      expect(
        result,
        UploadCostEstimate(
          pstFee: BigInt.zero,
          totalCost: BigInt.from(10),
          totalSize: 100,
          usdUploadCost: 10,
        ),
      );
    });
  });

  group('ConvertArToUSD', () {
    late ArweaveService arweaveService;
    late ConvertArToUSD convertArToUSD;

    setUp(() {
      arweaveService = MockArweaveService();
      convertArToUSD = ConvertArToUSD(arweave: arweaveService);
    });

    test(
        'convertForUSD should correctly call getArUsdConversionRateOrNull and calculate USD',
        () async {
      when(() => arweaveService.getArUsdConversionRateOrNull())
          .thenAnswer((_) => Future.value(1.5));

      final result = await convertArToUSD.convertForUSD(10.0);

      verify(() => arweaveService.getArUsdConversionRateOrNull()).called(1);
      expect(result, 15.0);
    });

    test(
        'convertForUSD should return null when getArUsdConversionRateOrNull returns null',
        () async {
      when(() => arweaveService.getArUsdConversionRateOrNull())
          .thenAnswer((_) => Future.value(null));

      final result = await convertArToUSD.convertForUSD(10.0);

      verify(() => arweaveService.getArUsdConversionRateOrNull()).called(1);
      expect(result, null);
    });
  });
}
