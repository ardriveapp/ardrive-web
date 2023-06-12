import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/data_size.dart';
import 'package:ardrive/utils/file_size_units.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

class MockPaymentService extends Mock implements PaymentService {}

class MockWallet extends Mock implements Wallet {}

class MockTurboSessionManager extends Mock implements TurboSessionManager {}

class MockTurboBalanceRetriever extends Mock implements TurboBalanceRetriever {}

class MockTurboPriceEstimator extends Mock implements TurboPriceEstimator {}

class MockTurboCostCalculator extends Mock implements TurboCostCalculator {}

class MockPaymentProvider extends Mock implements TurboPaymentProvider {}

void main() {
  group('Turbo', () {
    setUpAll(() {
      registerFallbackValue(getTestWallet());
    });
    group('getBalance', () {
      late TurboBalanceRetriever mockBalanceRetriever;
      late Turbo turbo;

      setUp(() {
        mockBalanceRetriever = MockTurboBalanceRetriever();
        turbo = Turbo(
          sessionManager: MockTurboSessionManager(),
          costCalculator: MockTurboCostCalculator(),
          balanceRetriever: mockBalanceRetriever,
          priceEstimator: MockTurboPriceEstimator(),
          wallet: MockWallet(),
          paymentProvider: MockPaymentProvider(),
        );
      });

      test('calls balanceRetriever.getBalance once', () async {
        final mockBalance = BigInt.from(100);
        when(() => mockBalanceRetriever.getBalance(any()))
            .thenAnswer((_) async => mockBalance);

        final balance = await turbo.getBalance();

        expect(balance, equals(mockBalance));
        verify(() => mockBalanceRetriever.getBalance(any())).called(1);
      });
    });

    group('getCostOfOneGB', () {
      late TurboCostCalculator mockCostCalculator;
      late Turbo turbo;

      setUp(() {
        mockCostCalculator = MockTurboCostCalculator();
        turbo = Turbo(
          sessionManager: MockTurboSessionManager(),
          costCalculator: mockCostCalculator,
          balanceRetriever: MockTurboBalanceRetriever(),
          priceEstimator: MockTurboPriceEstimator(),
          wallet: MockWallet(),
          paymentProvider: MockPaymentProvider(),
        );
      });

      test('calls costCalculator.getCostOfOneGB once', () async {
        final mockCost = BigInt.from(100);
        when(() => mockCostCalculator.getCostOfOneGB())
            .thenAnswer((_) async => mockCost);

        final cost = await turbo.getCostOfOneGB();

        expect(cost, equals(mockCost));
        verify(() => mockCostCalculator.getCostOfOneGB()).called(1);
      });
    });

    group('computePriceEstimate', () {
      late TurboPriceEstimator mockPriceEstimator;
      late Turbo turbo;

      setUp(() {
        mockPriceEstimator = MockTurboPriceEstimator();
        turbo = Turbo(
          sessionManager: MockTurboSessionManager(),
          costCalculator: MockTurboCostCalculator(),
          balanceRetriever: MockTurboBalanceRetriever(),
          priceEstimator: mockPriceEstimator,
          wallet: MockWallet(),
          paymentProvider: MockPaymentProvider(),
        );
      });

      test('calls priceEstimator.computePriceEstimate once', () async {
        final mockPriceEstimate = PriceEstimate(
          credits: BigInt.from(100),
          estimatedStorage: 1,
          priceInCurrency: 1,
        );

        when(() => mockPriceEstimator.computePriceEstimate(
              currentAmount: 100,
              currentDataUnit: FileSizeUnit.gigabytes,
              currentCurrency: 'usd',
            )).thenAnswer((_) async => mockPriceEstimate);

        final priceEstimate = await turbo.computePriceEstimate(
          currentAmount: 100,
          currentDataUnit: FileSizeUnit.gigabytes,
          currentCurrency: 'usd',
        );

        expect(priceEstimate, equals(mockPriceEstimate));
        verify(() => mockPriceEstimator.computePriceEstimate(
              currentAmount: 100,
              currentDataUnit: FileSizeUnit.gigabytes,
              currentCurrency: 'usd',
            )).called(1);
      });
    });

    group('computeStorageEstimateForCredits', () {
      late TurboPriceEstimator mockPriceEstimator;
      late Turbo turbo;

      setUp(() {
        mockPriceEstimator = MockTurboPriceEstimator();
        turbo = Turbo(
          sessionManager: MockTurboSessionManager(),
          costCalculator: MockTurboCostCalculator(),
          balanceRetriever: MockTurboBalanceRetriever(),
          priceEstimator: mockPriceEstimator,
          wallet: MockWallet(),
          paymentProvider: MockPaymentProvider(),
        );
      });

      test(
          'calls priceEstimator.computeStorageEstimateForCredits once with the correct arguments',
          () async {
        final mockStorageEstimate = 1.0;
        final mockCredits = BigInt.from(100);
        when(() => mockPriceEstimator.computeStorageEstimateForCredits(
              credits: mockCredits,
              outputDataUnit: FileSizeUnit.gigabytes,
            )).thenAnswer((_) async => mockStorageEstimate);

        final storageEstimate = await turbo.computeStorageEstimateForCredits(
          credits: mockCredits,
          outputDataUnit: FileSizeUnit.gigabytes,
        );

        expect(storageEstimate, equals(mockStorageEstimate));
        verify(() => mockPriceEstimator.computeStorageEstimateForCredits(
              credits: mockCredits,
              outputDataUnit: FileSizeUnit.gigabytes,
            )).called(1);
      });
    });

    group('priceEstimate updates when price quote expires', () {
      late TurboPriceEstimator mockPriceEstimator;
      late Turbo turbo;

      setUp(() {
        mockPriceEstimator = MockTurboPriceEstimator();
        turbo = Turbo(
          sessionManager: MockTurboSessionManager(),
          costCalculator: MockTurboCostCalculator(),
          balanceRetriever: MockTurboBalanceRetriever(),
          priceEstimator: mockPriceEstimator,
          wallet: MockWallet(),
          paymentProvider: MockPaymentProvider(),
        );
      });

      test('priceEstimate updates when price quote expires', () async {
        fakeAsync((async) async {
          final mockStorageEstimate = 1.0;
          final mockCredits = BigInt.from(100);

          final mockPriceEstimate1 = PriceEstimate(
            credits: BigInt.from(100),
            estimatedStorage: 1,
            priceInCurrency: 1,
          );

          final mockPriceEstimate2 = PriceEstimate(
            credits: BigInt.from(200),
            estimatedStorage: 2,
            priceInCurrency: 2,
          );

          late PriceEstimate priceEstimate;

          turbo.onPriceEstimateChanged.listen((event) {
            priceEstimate = event;
          });

          when(() => mockPriceEstimator.computePriceEstimate(
                currentAmount: 100,
                currentDataUnit: FileSizeUnit.gigabytes,
                currentCurrency: 'usd',
              )).thenAnswer((_) async => mockPriceEstimate1);

          async.elapse(const Duration(minutes: 5));

          expect(priceEstimate, mockPriceEstimate1);

          await Future.delayed(Duration(seconds: 2));

          when(() => mockPriceEstimator.computePriceEstimate(
                currentAmount: 100,
                currentDataUnit: FileSizeUnit.gigabytes,
                currentCurrency: 'usd',
              )).thenAnswer((_) async => mockPriceEstimate2);

          async.elapse(const Duration(minutes: 5));

          expect(priceEstimate, mockPriceEstimate2);
        });
      });
      test(
          'priceEstimate updates when price quote expires even if the user doenst select any amount',
          () async {
        fakeAsync((async) async {
          final mockPriceEstimate = PriceEstimate(
            credits: BigInt.from(0),
            estimatedStorage: 0,
            priceInCurrency: 0,
          );

          late PriceEstimate priceEstimate;

          turbo.onPriceEstimateChanged.listen((event) {
            priceEstimate = event;
          });

          when(() => mockPriceEstimator.computePriceEstimate(
                currentAmount: 0,
                currentDataUnit: FileSizeUnit.gigabytes,
                currentCurrency: 'usd',
              )).thenAnswer((_) async => mockPriceEstimate);

          async.elapse(const Duration(minutes: 5));

          expect(priceEstimate, mockPriceEstimate);

          await Future.delayed(Duration(seconds: 2));

          when(() => mockPriceEstimator.computePriceEstimate(
                currentAmount: 0,
                currentDataUnit: FileSizeUnit.gigabytes,
                currentCurrency: 'usd',
              )).thenAnswer((_) async => mockPriceEstimate);

          async.elapse(const Duration(minutes: 5));

          expect(priceEstimate, mockPriceEstimate);
        });
      });
    });

    group('dispose', () {
      late MockTurboSessionManager mockSessionManager;
      late Turbo turbo;

      setUp(() {
        mockSessionManager = MockTurboSessionManager();
        turbo = Turbo(
          sessionManager: MockTurboSessionManager(),
          costCalculator: MockTurboCostCalculator(),
          balanceRetriever: MockTurboBalanceRetriever(),
          priceEstimator: MockTurboPriceEstimator(),
          wallet: MockWallet(),
          paymentProvider: MockPaymentProvider(),
        );
      });

      test('calls priceEstimator.dispose once', () async {
        bool canceledTimer = true;

        // won't update priceEstimate anymore
        fakeAsync((async) async {
          turbo.onPriceEstimateChanged.listen((event) {
            canceledTimer = false;
          });

          await turbo.dispose();

          async.elapse(const Duration(minutes: 5));

          expect(canceledTimer, isTrue);
          verify(() => mockSessionManager.dispose()).called(1);
        });
      });
    });

    group('refreshPriceEstimate', () {
      late MockTurboSessionManager mockSessionManager;
      late MockTurboBalanceRetriever mockBalanceRetriever;
      late MockTurboPriceEstimator mockPriceEstimator;
      late Turbo turbo;

      setUp(() {
        mockSessionManager = MockTurboSessionManager();
        mockBalanceRetriever = MockTurboBalanceRetriever();
        mockPriceEstimator = MockTurboPriceEstimator();
        turbo = Turbo(
          sessionManager: mockSessionManager,
          costCalculator: MockTurboCostCalculator(),
          balanceRetriever: mockBalanceRetriever,
          priceEstimator: mockPriceEstimator,
          wallet: MockWallet(),
          paymentProvider: MockPaymentProvider(),
        );
      });

      test('calls sessionManager.refresh once', () async {
        final mockPriceEstimate = PriceEstimate(
          credits: BigInt.from(100),
          estimatedStorage: 1,
          priceInCurrency: 1,
        );

        when(() => mockPriceEstimator.computePriceEstimate(
              currentAmount: 100,
              currentDataUnit: FileSizeUnit.gigabytes,
              currentCurrency: 'usd',
            )).thenAnswer((_) async => mockPriceEstimate);

        /// calculates the price estimate first
        await turbo.computePriceEstimate(
          currentAmount: 100,
          currentDataUnit: FileSizeUnit.gigabytes,
          currentCurrency: 'usd',
        );

        await turbo.refreshPriceEstimate();

        // must call computePriceEstimate twice with the same parameters
        verify(() => mockPriceEstimator.computePriceEstimate(
              currentAmount: 100,
              currentDataUnit: FileSizeUnit.gigabytes,
              currentCurrency: 'usd',
            )).called(2);
      });

      test(
          'throws AssertionError when the client tries to refresh without first computating the price estimate',
          () async {
        expect(turbo.refreshPriceEstimate(), throwsAssertionError);
      });
    });

    group('testing currentPriceEstimate', () {
      test('returns PriceEstimate.zero when priceEstimate is not yet computed',
          () async {
        final mockSessionManager = MockTurboSessionManager();
        final mockBalanceRetriever = MockTurboBalanceRetriever();
        final mockPriceEstimator = MockTurboPriceEstimator();
        final turbo = Turbo(
          sessionManager: mockSessionManager,
          costCalculator: MockTurboCostCalculator(),
          balanceRetriever: mockBalanceRetriever,
          priceEstimator: mockPriceEstimator,
          wallet: MockWallet(),
          paymentProvider: MockPaymentProvider(),
        );

        expect(turbo.currentPriceEstimate, PriceEstimate.zero());
      });

      test('returns the last fetched priceEstimate', () async {
        final mockSessionManager = MockTurboSessionManager();
        final mockBalanceRetriever = MockTurboBalanceRetriever();
        final mockPriceEstimator = MockTurboPriceEstimator();

        final turbo = Turbo(
          sessionManager: mockSessionManager,
          costCalculator: MockTurboCostCalculator(),
          balanceRetriever: mockBalanceRetriever,
          priceEstimator: mockPriceEstimator,
          wallet: MockWallet(),
          paymentProvider: MockPaymentProvider(),
        );

        final mockPriceEstimate100 = PriceEstimate(
          credits: BigInt.from(100),
          estimatedStorage: 1,
          priceInCurrency: 1,
        );
        final mockPriceEstimate200 = PriceEstimate(
          credits: BigInt.from(200),
          estimatedStorage: 2,
          priceInCurrency: 2,
        );

        when(() => mockPriceEstimator.computePriceEstimate(
              currentAmount: 100,
              currentDataUnit: FileSizeUnit.gigabytes,
              currentCurrency: 'usd',
            )).thenAnswer((_) async => mockPriceEstimate100);

        final computedPriceEstimate = await turbo.computePriceEstimate(
          currentAmount: 100,
          currentDataUnit: FileSizeUnit.gigabytes,
          currentCurrency: 'usd',
        );

        expect(turbo.currentPriceEstimate, computedPriceEstimate);

        /// returns a different one for test purpuses
        when(() => mockPriceEstimator.computePriceEstimate(
              currentAmount: 200,
              currentDataUnit: FileSizeUnit.gigabytes,
              currentCurrency: 'usd',
            )).thenAnswer((_) async => mockPriceEstimate200);

        final refreshedPriceEstimate = await turbo.refreshPriceEstimate();

        expect(turbo.currentPriceEstimate, refreshedPriceEstimate);
      });
    });

    group('maxQuoteExpirationDate', () {
      test('throws an Exception when priceEstimate is not yet computed',
          () async {
        final mockSessionManager = MockTurboSessionManager();
        final mockBalanceRetriever = MockTurboBalanceRetriever();
        final mockPriceEstimator = MockTurboPriceEstimator();

        final turbo = Turbo(
          sessionManager: mockSessionManager,
          costCalculator: MockTurboCostCalculator(),
          balanceRetriever: mockBalanceRetriever,
          priceEstimator: mockPriceEstimator,
          wallet: MockWallet(),
          paymentProvider: MockPaymentProvider(),
        );

        expect(() => turbo.maxQuoteExpirationDate, throwsA(isA<Exception>()));
      });

      test(
          'returns the maxQuoteExpirationDate of the last fetched priceEstimate',
          () async {
        final mockSessionManager = MockTurboSessionManager();
        final mockBalanceRetriever = MockTurboBalanceRetriever();
        final mockPriceEstimator = MockTurboPriceEstimator();

        final turbo = Turbo(
          sessionManager: mockSessionManager,
          costCalculator: MockTurboCostCalculator(),
          balanceRetriever: mockBalanceRetriever,
          priceEstimator: mockPriceEstimator,
          wallet: MockWallet(),
          paymentProvider: MockPaymentProvider(),
        );

        final mockPriceEstimate100 = PriceEstimate(
          credits: BigInt.from(100),
          estimatedStorage: 1,
          priceInCurrency: 1,
        );

        when(() => mockPriceEstimator.maxQuoteExpirationTime)
            .thenAnswer((_) => DateTime.now());

        when(() => mockPriceEstimator.computePriceEstimate(
              currentAmount: 100,
              currentDataUnit: FileSizeUnit.gigabytes,
              currentCurrency: 'usd',
            )).thenAnswer((_) async => mockPriceEstimate100);

        await turbo.computePriceEstimate(
          currentAmount: 100,
          currentDataUnit: FileSizeUnit.gigabytes,
          currentCurrency: 'usd',
        );

        turbo.maxQuoteExpirationDate;

        verify(() => mockPriceEstimator.maxQuoteExpirationTime).called(1);
      });
    });
  });

  group('TurboCostCalculator', () {
    late TurboCostCalculator costCalculator;
    late MockPaymentService mockPaymentService;

    setUp(() {
      mockPaymentService = MockPaymentService();
      costCalculator = TurboCostCalculator(paymentService: mockPaymentService);
    });

    test('getCostOfOneGB calls PaymentService.getPriceForBytes once', () async {
      final mockCost = BigInt.from(100);
      final byteSize = const GiB(1).size;
      when(() => mockPaymentService.getPriceForBytes(byteSize: byteSize))
          .thenAnswer((_) async => mockCost);

      final cost = await costCalculator.getCostOfOneGB();

      expect(cost, equals(mockCost));
      verify(() => mockPaymentService.getPriceForBytes(byteSize: byteSize))
          .called(1);
    });

    test(
        'getCostOfOneGB returns cached cost if fetched less than 10 minutes ago',
        () async {
      final mockCost = BigInt.from(100);
      final byteSize = const GiB(1).size;
      when(() => mockPaymentService.getPriceForBytes(byteSize: byteSize))
          .thenAnswer((_) async => mockCost);

      // fetch cost twice
      await costCalculator.getCostOfOneGB();
      final cost = await costCalculator.getCostOfOneGB();

      // should still equal mockCost, and PaymentService.getPriceForBytes should only be called once due to caching
      expect(cost, equals(mockCost));
      verify(() => mockPaymentService.getPriceForBytes(byteSize: byteSize))
          .called(1);
    });
  });

  group('TurboBalanceRetriever', () {
    late TurboBalanceRetriever balanceRetriever;
    late MockPaymentService mockPaymentService;
    late MockWallet mockWallet;

    setUp(() {
      mockPaymentService = MockPaymentService();
      mockWallet = MockWallet();
      balanceRetriever =
          TurboBalanceRetriever(paymentService: mockPaymentService);
    });

    test('getBalance calls PaymentService.getBalance', () async {
      final mockBalance = BigInt.from(100);
      when(() => mockPaymentService.getBalance(wallet: mockWallet))
          .thenAnswer((_) async => mockBalance);

      final balance = await balanceRetriever.getBalance(mockWallet);

      expect(balance, equals(mockBalance));
      verify(() => mockPaymentService.getBalance(wallet: mockWallet)).called(1);
    });
  });
  group('TurboSessionManager', () {
    late TurboSessionManager sessionManager;

    setUp(() {
      sessionManager = TurboSessionManager();
    });

    tearDown(() async {
      await sessionManager.dispose();
    });

    test('onSessionExpired emits true after 25 minutes', () {
      fakeAsync((async) async {
        // listen for session expired event
        bool expired = false;

        sessionManager.onSessionExpired.listen((value) async {
          expired = value;
          expect(expired, isFalse);
          await Future.delayed(const Duration(seconds: 2));
          expect(expired, isTrue);
        });

        await Future.delayed(const Duration(seconds: 2));
        async.elapse(const Duration(minutes: 25));
      });
    });

    test('onSessionExpired does not emit before 25 minutes', () {
      fakeAsync((async) async {
        // listen for session expired event
        bool expired = false;

        sessionManager.onSessionExpired.listen((value) async {
          expired = value;
          expect(expired, isFalse);
          await Future.delayed(const Duration(seconds: 2));
          expect(expired, isFalse);
        });

        await Future.delayed(const Duration(seconds: 2));
        async.elapse(const Duration(minutes: 24, seconds: 54));
      });
    });

    test('dispose cancels the session expiration timer', () {
      fakeAsync((async) async {
        // listen for session expired event
        bool expired = false;

        sessionManager.onSessionExpired.listen((value) {
          logger.i('expired: $value');
          expired = value;
        });

        // dispose the sessionManager
        sessionManager.dispose();

        logger.i('elapsed 24 minutes');

        // advance time by 25 minutes
        async.elapse(const Duration(minutes: 25));

        logger.i('elapsed 25 minutes');

        // assert that expired is still false
        expect(expired, isFalse);
      });
    });
  });

  group('TurboPriceEstimator', () {
    late MockPaymentService mockPaymentService;
    late MockTurboCostCalculator mockTurboCostCalculator;
    late TurboPriceEstimator turboPriceEstimator;

    setUp(() {
      mockPaymentService = MockPaymentService();
      mockTurboCostCalculator = MockTurboCostCalculator();
      turboPriceEstimator = TurboPriceEstimator(
        paymentService: mockPaymentService,
        costCalculator: mockTurboCostCalculator,
      );
    });

    test('computePriceEstimate should return correct estimate', () async {
      // Setup the method call response
      const currentAmount = 1;
      const currentCurrency = 'USD';
      const currentDataUnit = FileSizeUnit.gigabytes;

      final expectedCredits = BigInt.from(100);
      const expectedEstimatedStorage = 1.0;

      when(() => mockPaymentService.getPriceForFiat(
            currency: currentCurrency,
            amount: currentAmount * 100,
          )).thenAnswer((_) async => expectedCredits);

      when(() => mockTurboCostCalculator.getCostOfOneGB())
          .thenAnswer((_) async => expectedCredits);

      // Call the method
      final priceEstimate = await turboPriceEstimator.computePriceEstimate(
        currentAmount: currentAmount,
        currentCurrency: currentCurrency,
        currentDataUnit: currentDataUnit,
      );

      // Verify the result
      expect(priceEstimate.credits, expectedCredits);
      expect(priceEstimate.priceInCurrency, currentAmount);
      expect(priceEstimate.estimatedStorage, expectedEstimatedStorage);
    });

    group("computeStorageEstimateForCredits", () {
      test('should return correct estimate', () async {
        // Setup the method call response
        final expectedCredits = BigInt.from(100);
        const expectedEstimatedStorage = 1.0;
        const outputDataUnit = FileSizeUnit.gigabytes;

        when(() => mockTurboCostCalculator.getCostOfOneGB())
            .thenAnswer((_) async => expectedCredits);

        // Call the method
        final estimatedStorage =
            await turboPriceEstimator.computeStorageEstimateForCredits(
          credits: expectedCredits,
          outputDataUnit: outputDataUnit,
        );

        // Verify the result
        expect(estimatedStorage, expectedEstimatedStorage);
      });

      test('should return correct estimate using MiB', () async {
        // Setup the method call response
        final expectedCredits = BigInt.from(100);
        final costOfOneGB = BigInt.from(100);
        final expectedEstimatedStorage =
            (const MiB(1024).size) / (const MiB(1).size); // 1GiB in MiB
        const outputDataUnit = FileSizeUnit.megabytes;

        when(() => mockTurboCostCalculator.getCostOfOneGB())
            .thenAnswer((_) async => costOfOneGB);

        // Call the method
        final estimatedStorage =
            await turboPriceEstimator.computeStorageEstimateForCredits(
          credits: expectedCredits,
          outputDataUnit: outputDataUnit,
        );

        // Verify the result
        expect(estimatedStorage, expectedEstimatedStorage);
      });

      test('should return correct estimate KiB', () async {
        // Setup the method call response
        final expectedCredits = BigInt.from(100);
        final costOfOneGB = BigInt.from(100);
        final expectedEstimatedStorage =
            (const GiB(1).size) / (const KiB(1).size); // 1GiB in MiB
        const outputDataUnit = FileSizeUnit.kilobytes;

        when(() => mockTurboCostCalculator.getCostOfOneGB())
            .thenAnswer((_) async => costOfOneGB);

        // Call the method
        final estimatedStorage =
            await turboPriceEstimator.computeStorageEstimateForCredits(
          credits: expectedCredits,
          outputDataUnit: outputDataUnit,
        );

        // Verify the result
        expect(estimatedStorage, expectedEstimatedStorage);
      });

      test('should return correct estimate using GiB', () async {
        // Setup the method call response
        final expectedCredits = BigInt.from(0);
        const expectedEstimatedStorage = 0;

        const outputDataUnit = FileSizeUnit.gigabytes;

        when(() => mockTurboCostCalculator.getCostOfOneGB())
            .thenAnswer((_) async => BigInt.from(1));

        // Call the method
        final estimatedStorage =
            await turboPriceEstimator.computeStorageEstimateForCredits(
          credits: expectedCredits,
          outputDataUnit: outputDataUnit,
        );

        // Verify the result
        expect(estimatedStorage, expectedEstimatedStorage);
      });
    });
  });
}
