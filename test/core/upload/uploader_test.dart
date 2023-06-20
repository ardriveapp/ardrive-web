import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/upload/models/upload_plan.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/blocs/upload/upload_handles/handles.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/size_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class MockBundleUploader extends Mock implements BundleUploader {}

class MockFileV2Uploader extends Mock implements FileV2Uploader {}

class MockBundleUploadHandle extends Mock implements BundleUploadHandle {}

class MockFileV2UploadHandle extends Mock implements FileV2UploadHandle {}

class MockTurboUploadService extends Mock implements TurboUploadService {}

class MockArweave extends Mock implements Arweave {}

class MockTransactionUpload extends Mock implements TransactionUploader {}

class MockTurboBalanceRetriever extends Mock implements TurboBalanceRetriever {}

class MockUploadCostEstimateCalculatorForAR extends Mock
    implements UploadCostEstimateCalculatorForAR {}

class MockTurboUploadCostCalculator extends Mock
    implements TurboUploadCostCalculator {}

class MockArDriveAuth extends Mock implements ArDriveAuth {}

class MockSizeUtils extends Mock implements SizeUtils {}

class MockConfigService extends Mock implements ConfigService {}

class MockUploadPlan extends Mock implements UploadPlan {}

class MockUploadPaymentInfo extends Mock implements UploadPaymentInfo {}

class MockUploadCostEstimate extends Mock implements UploadCostEstimate {}

void main() {
  ArDriveUploader uploader;
  MockBundleUploader bundleUploader;
  MockFileV2Uploader fileV2Uploader;

  bundleUploader = MockBundleUploader();
  fileV2Uploader = MockFileV2Uploader();
  uploader = ArDriveUploader(
    bundleUploader: bundleUploader,
    fileV2Uploader: fileV2Uploader,
    prepareBundle: (handle) async {},
    prepareFile: (handle) async {},
    onFinishBundleUpload: (handle) async {},
    onFinishFileUpload: (handle) async {},
    onUploadBundleError: (handle, error) async {},
    onUploadFileError: (handle, error) async {},
  );

  group('ArDriveUploader', () {
    group('uploadFromHandles', () {
      test('emits correct overall progress', () async {
        var mockBundleHandle = MockBundleUploadHandle();
        var mockFileV2Handle = MockFileV2UploadHandle();

        when(() => bundleUploader.upload(mockBundleHandle)).thenAnswer(
          (_) => Stream<double>.fromIterable([0.1, 0.5, 1.0]),
        );
        when(() => fileV2Uploader.upload(mockFileV2Handle)).thenAnswer(
          (_) => Stream<double>.fromIterable([0.1, 0.7, 1.0]),
        );

        expect(
          uploader.uploadFromHandles(
            bundleHandles: [mockBundleHandle],
            fileV2Handles: [mockFileV2Handle],
          ),
          emitsInOrder([
            // (0.1 / 2) (from bundle handle) 5%
            closeTo(0.05, 0.001),
            // (0.1 / 2) 10% (from file handle) + (0.1 / 2) 5% (from bundle handle) 10%
            closeTo(0.1, 0.001),
            // (0.5 / 2) 25% (from bundle handle) + (0.1 / 2) 5% (from file handle) 30%
            closeTo(0.3, 0.001),
            // (0.7 / 2) 35% (from file handle) + (0.5 / 2) 25% (from bundle handle) 60%
            closeTo(0.6, 0.001),
            // (1.0 / 2) 50% (from bundle handle) + (0.7 / 2) 35% (from file handle) 85%
            closeTo(0.85, 0.001),
            // (1.0 / 2) 50% (from file handle) + (1.0 / 2) 50% (from bundle handle) 100%
            closeTo(1.0, 0.001),
            emitsDone,
          ]),
        );
      });

      test('emits correct overall progress', () async {
        var mockBundleHandle = MockBundleUploadHandle();
        var mockFileV2Handle = MockFileV2UploadHandle();

        when(() => bundleUploader.upload(mockBundleHandle)).thenAnswer(
          (_) => Stream<double>.fromIterable([0.25, 0.5, 0.6, 1.0]),
        );
        when(() => fileV2Uploader.upload(mockFileV2Handle)).thenAnswer(
          (_) => Stream<double>.fromIterable([0.1, 0.75, 1.0]),
        );

        expect(
          uploader.uploadFromHandles(
            bundleHandles: [mockBundleHandle],
            fileV2Handles: [mockFileV2Handle],
          ),
          emitsInOrder([
            // (0.25 / 2) (from bundle handle) 12.5%
            closeTo(0.125, 0.001),
            // (0.25 / 2) 12.5% (from file handle) + (0.1 / 2) 5% (from bundle handle) 17.5%
            closeTo(0.175, 0.001),
            // (0.5 / 2) 25% (from bundle handle) + (0.1 / 2) 5% (from file handle) 30%
            closeTo(0.3, 0.001),
            // (0.5 / 2) 25% (from file handle) + (0.75 / 2) 37.5% (from bundle handle) 62.5%
            closeTo(0.625, 0.001),
            // (0.6 / 2) 30% (from bundle handle) + (0.75 / 2) 37.5% (from file handle) 67.5%
            closeTo(0.675, 0.001),
            // (0.6 / 2) 30% (from file handle) + (1.0 / 2) 50% (from bundle handle) 80%
            closeTo(0.8, 0.001),
            // (1.0 / 2) 50% (from file handle) + (1.0 / 2) 50% (from bundle handle) 100%
            closeTo(1.0, 0.001),
            emitsDone,
          ]),
        );
      });
    });
  });

  group('Uploader implementations', () {
    late TurboUploader turboUploader;

    late MockTurboUploadService turboUploadService;
    late MockBundleUploadHandle bundleHandle;

    setUp(() {
      turboUploadService = MockTurboUploadService();
      bundleHandle = MockBundleUploadHandle();

      turboUploader = TurboUploader(turboUploadService, getTestWallet());

      registerFallbackValue(DataItem());
      registerFallbackValue(Wallet());
    });

    group('TurboUploader', () {
      test('upload correctly emits progress', () async {
        when(() => bundleHandle.bundleDataItem).thenReturn(DataItem());
        when(() => turboUploadService.postDataItem(
                dataItem: any(named: 'dataItem'), wallet: any(named: 'wallet')))
            .thenAnswer((_) async => 'mockTransactionId');
        await expectLater(
          turboUploader.upload(bundleHandle),
          emitsInOrder([1.0, emitsDone]),
        );
      });
    });

    group('ArweaveBundleUploader', () {
      test('upload correctly emits progress', () async {
        // TODO: tech debt. We need to export the `ArweaveTransactionsApi` on the arweave-dart package
      });
    });

    group('FileV2Uploader', () {
      // TODO: tech debt. We need to export the `ArweaveTransactionsApi` on the arweave-dart package
    });
  });

  group('UploadPaymentEvaluator', () {
    late UploadPaymentEvaluator uploadPaymentEvaluator;
    late MockTurboBalanceRetriever turboBalanceRetriever;
    late MockUploadCostEstimateCalculatorForAR
        uploadCostEstimateCalculatorForAR;
    late MockTurboUploadCostCalculator turboUploadCostCalculator;
    late MockArDriveAuth auth;
    late MockSizeUtils sizeUtils;
    late MockConfigService configService;
    late MockUploadPlan uploadPlan;

    final mockUploadCostEstimateAR = UploadCostEstimate(
      totalCost: BigInt.from(100),
      pstFee: BigInt.from(10),
      totalSize: 200,
      usdUploadCost: 25,
    );

    /// total cost 400
    final mockUploadCostEstimateTurbo = UploadCostEstimate(
      totalCost: BigInt.from(400),
      pstFee: BigInt.from(40),
      totalSize: 1000,
      usdUploadCost: 100,
    );

    setUpAll(() {
      turboBalanceRetriever = MockTurboBalanceRetriever();
      uploadCostEstimateCalculatorForAR =
          MockUploadCostEstimateCalculatorForAR();
      turboUploadCostCalculator = MockTurboUploadCostCalculator();
      auth = MockArDriveAuth();
      sizeUtils = MockSizeUtils();
      configService = MockConfigService();
      uploadPaymentEvaluator = UploadPaymentEvaluator(
        turboBalanceRetriever: turboBalanceRetriever,
        uploadCostEstimateCalculatorForAR: uploadCostEstimateCalculatorForAR,
        auth: auth,
        turboUploadCostCalculator: turboUploadCostCalculator,
        appConfig: getFakeConfig(),
      );
      uploadPlan = MockUploadPlan();
      registerFallbackValue(Wallet());

      when(() => uploadPlan.bundleUploadHandles).thenReturn([]);
      when(() => uploadPlan.fileV2UploadHandles).thenReturn({});
      when(() => auth.currentUser).thenAnswer((_) => getFakeUser());

      /// 500 balance
      when(() => turboBalanceRetriever.getBalance(any()))
          .thenAnswer((_) async => BigInt.from(500));
      when(() => sizeUtils.getSizeOfAllBundles(any()))
          .thenAnswer((_) async => 200);
      when(() => sizeUtils.getSizeOfAllV2Files(any()))
          .thenAnswer((_) async => 200);

      when(() => uploadCostEstimateCalculatorForAR.calculateCost(
              totalSize: any(named: 'totalSize')))
          .thenAnswer((_) async => mockUploadCostEstimateAR);
      when(() => turboUploadCostCalculator.calculateCost(
              totalSize: any(named: 'totalSize')))
          .thenAnswer((_) async => mockUploadCostEstimateTurbo);
    });

    group('getUploadPaymentInfo', () {
      test(
          'getUploadPaymentInfo assigns UploadMethod.turbo when turbo balance is enough',
          () async {
        final result = await uploadPaymentEvaluator.getUploadPaymentInfo(
          uploadPlanForAR: uploadPlan,
          uploadPlanForTurbo: uploadPlan,
        );

        expect(result.defaultPaymentMethod, equals(UploadMethod.turbo));
        expect(result.isTurboUploadPossible, isTrue);
      });
      test(
          'getUploadPaymentInfo assigns UploadMethod.ar when turbo balance is not enough',
          () async {
        // 400 total cost
        final mockUploadCostEstimateTurbo = UploadCostEstimate(
          totalCost: BigInt.from(400),
          pstFee: BigInt.from(40),
          totalSize: 1000,
          usdUploadCost: 100,
        );

        // balance 100
        when(() => turboBalanceRetriever.getBalance(any()))
            .thenAnswer((_) async => BigInt.from(100));

        when(() => turboUploadCostCalculator.calculateCost(
                totalSize: any(named: 'totalSize')))
            .thenAnswer((_) async => mockUploadCostEstimateTurbo);

        final result = await uploadPaymentEvaluator.getUploadPaymentInfo(
          uploadPlanForAR: uploadPlan,
          uploadPlanForTurbo: uploadPlan,
        );

        expect(result.defaultPaymentMethod, equals(UploadMethod.ar));
        expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
      });
      test(
          'isFreeUploadPossibleUsingTurbo returns true when all file sizes are within turbo threshold',
          () async {
        final mockFile = MockBundleUploadHandle();
        when(() => mockFile.size).thenReturn(499);
        // limit of 500
        when(() => mockFile.computeBundleSize())
            .thenAnswer((invocation) => Future.value(499));

        when(() => uploadPlan.bundleUploadHandles).thenReturn([mockFile]);

        final result = await uploadPaymentEvaluator.getUploadPaymentInfo(
          uploadPlanForAR: uploadPlan,
          uploadPlanForTurbo: uploadPlan,
        );

        expect(result.isFreeUploadPossibleUsingTurbo, isTrue);
        expect(result.isTurboUploadPossible, isTrue);
      });
      test(
          'isFreeUploadPossibleUsingTurbo returns false when not all file sizes are within turbo threshold',
          () async {
        final mockFile = MockBundleUploadHandle();
        when(() => mockFile.size).thenReturn(501);
        // limit of 500
        when(() => mockFile.computeBundleSize())
            .thenAnswer((invocation) => Future.value(501));

        when(() => uploadPlan.bundleUploadHandles).thenReturn([mockFile]);

        final result = await uploadPaymentEvaluator.getUploadPaymentInfo(
          uploadPlanForAR: uploadPlan,
          uploadPlanForTurbo: uploadPlan,
        );

        expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
        expect(result.isTurboUploadPossible, isTrue);
      });

      test('isTurboUploadPossible returns true when have bundles', () async {
        final mockFile = MockBundleUploadHandle();
        when(() => mockFile.size).thenReturn(501);
        // limit of 500
        when(() => mockFile.computeBundleSize())
            .thenAnswer((invocation) => Future.value(501));

        when(() => uploadPlan.bundleUploadHandles).thenReturn([mockFile]);

        final result = await uploadPaymentEvaluator.getUploadPaymentInfo(
          uploadPlanForAR: uploadPlan,
          uploadPlanForTurbo: uploadPlan,
        );

        expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
        expect(result.isTurboUploadPossible, isTrue);
      });
      test('isTurboUploadPossible returns false when not have any bundles',
          () async {
        final mockFile = MockBundleUploadHandle();
        when(() => mockFile.size).thenReturn(501);
        // limit of 500
        when(() => mockFile.computeBundleSize())
            .thenAnswer((invocation) => Future.value(501));

        when(() => uploadPlan.bundleUploadHandles).thenReturn([]);

        final result = await uploadPaymentEvaluator.getUploadPaymentInfo(
          uploadPlanForAR: uploadPlan,
          uploadPlanForTurbo: uploadPlan,
        );

        expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
        expect(result.isTurboUploadPossible, isFalse);
      });

      test('returns the expected UploadPaymentInfo', () async {
        final mockFile = MockBundleUploadHandle();
        when(() => mockFile.size).thenReturn(501);

        when(() => uploadPlan.bundleUploadHandles).thenReturn([mockFile]);
        when(() => turboBalanceRetriever.getBalance(any()))
            .thenAnswer((_) async => BigInt.from(500));

        // limit of 500
        when(() => mockFile.computeBundleSize())
            .thenAnswer((invocation) => Future.value(501));

        final result = await uploadPaymentEvaluator.getUploadPaymentInfo(
          uploadPlanForAR: uploadPlan,
          uploadPlanForTurbo: uploadPlan,
        );

        expect(result.arCostEstimate, mockUploadCostEstimateAR);
        expect(result.turboCostEstimate, mockUploadCostEstimateTurbo);
        expect(result.defaultPaymentMethod, equals(UploadMethod.turbo));
        expect(result.isTurboUploadPossible, isTrue);
        expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
      });

      test('returns the expected UploadPaymentInfo', () async {
        final mockFile = MockBundleUploadHandle();
        when(() => mockFile.size).thenReturn(501);
        // limit of 500
        when(() => mockFile.computeBundleSize())
            .thenAnswer((invocation) => Future.value(501));

        when(() => uploadPlan.bundleUploadHandles).thenReturn([mockFile]);
        // 400 total cost
        final mockUploadCostEstimateTurbo = UploadCostEstimate(
          totalCost: BigInt.from(400),
          pstFee: BigInt.from(40),
          totalSize: 1000,
          usdUploadCost: 100,
        );

        // balance 100
        when(() => turboBalanceRetriever.getBalance(any()))
            .thenAnswer((_) async => BigInt.from(100));

        when(() => turboUploadCostCalculator.calculateCost(
                totalSize: any(named: 'totalSize')))
            .thenAnswer((_) async => mockUploadCostEstimateTurbo);

        final result = await uploadPaymentEvaluator.getUploadPaymentInfo(
          uploadPlanForAR: uploadPlan,
          uploadPlanForTurbo: uploadPlan,
        );

        expect(result.arCostEstimate, mockUploadCostEstimateAR);
        expect(result.turboCostEstimate, mockUploadCostEstimateTurbo);
        expect(result.defaultPaymentMethod, equals(UploadMethod.ar));
        expect(result.isTurboUploadPossible, isTrue);
        expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
      });
    });
  });
}

AppConfig getFakeConfig() =>
    AppConfig(allowedDataItemSizeForTurbo: 500, stripePublishableKey: '');

User getFakeUser() => User(
    password: 'password',
    wallet: getTestWallet(),
    walletAddress: 'walletAddress',
    walletBalance: BigInt.one,
    cipherKey: SecretKey([]),
    profileType: ProfileType.arConnect);
