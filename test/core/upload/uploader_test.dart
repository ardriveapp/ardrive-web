import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/upload/models/models.dart';
import 'package:ardrive/blocs/upload/models/upload_plan.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/blocs/upload/upload_handles/handles.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/size_utils.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
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

class MockUploadPlan extends Mock implements UploadPlan {}

class MockUploadPaymentInfo extends Mock implements UploadPaymentInfo {}

class MockUploadCostEstimate extends Mock implements UploadCostEstimate {}

class MockUploadPlanUtils extends Mock implements UploadPlanUtils {}

class MockUploadParams extends Mock implements UploadParams {}

class MockUploadPreparer extends Mock implements UploadPreparer {}

class MockFileDataItemUploadHandle extends Mock
    implements FileDataItemUploadHandle {}

class MockUploadPaymentEvaluator extends Mock
    implements UploadPaymentEvaluator {}

void main() {
  ArDriveUploaderFromHandles uploader;
  MockBundleUploader bundleUploader;
  MockFileV2Uploader fileV2Uploader;

  bundleUploader = MockBundleUploader();
  fileV2Uploader = MockFileV2Uploader();
  uploader = ArDriveUploaderFromHandles(
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

        when(() => mockBundleHandle.size).thenReturn(100);
        when(() => mockFileV2Handle.size).thenReturn(100);

        when(() => bundleUploader.upload(mockBundleHandle)).thenAnswer(
          (_) => Stream<double>.fromIterable([0.1, 0.5, 1.0]),
        );
        when(() => bundleUploader.useTurbo).thenReturn(false);

        when(() => fileV2Uploader.upload(mockFileV2Handle)).thenAnswer(
          (_) => Stream<double>.fromIterable([0.1, 0.7, 1.0]),
        );

        expect(
          uploader.uploadFromHandles(
            bundleHandles: [mockBundleHandle],
            fileV2Handles: [mockFileV2Handle],
            enableLogs: false,
          ),
          emitsInOrder([
            // (0.1 / 2) (from bundle handle) 5%
            closeTo(0.05, 0.001),
            // (0.1 / 2) 10% (from file handle) + (0.1 / 2) 5% (from bundle handle) 10%
            closeTo(0.25, 0.001),
            // (0.5 / 2) 25% (from bundle handle) + (0.1 / 2) 5% (from file handle) 30%
            closeTo(0.5, 0.001),
            // (0.7 / 2) 35% (from file handle) + (0.5 / 2) 25% (from bundle handle) 60%
            closeTo(0.55, 0.001),
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

        when(() => mockBundleHandle.size).thenReturn(100);
        when(() => mockFileV2Handle.size).thenReturn(100);

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
            enableLogs: false,
          ),
          emitsInOrder([
            // (0.25 / 2) (from bundle handle) 12.5%
            closeTo(0.125, 0.001),
            // (0.25 / 2) 12.5% (from file handle) + (0.1 / 2) 5% (from bundle handle) 17.5%
            closeTo(0.25, 0.001),
            // (0.5 / 2) 25% (from bundle handle) + (0.1 / 2) 5% (from file handle) 30%
            closeTo(0.3, 0.001),
            // (0.5 / 2) 25% (from file handle) + (0.75 / 2) 37.5% (from bundle handle) 62.5%
            closeTo(0.5, 0.001),
            // (0.6 / 2) 30% (from bundle handle) + (0.75 / 2) 37.5% (from file handle) 67.5%
            closeTo(0.55, 0.001),
            // (0.6 / 2) 30% (from file handle) + (1.0 / 2) 50% (from bundle handle) 80%
            closeTo(0.875, 0.001),
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
        when(() => turboUploadService.postDataItemWithProgress(
                dataItem: any(named: 'dataItem'), wallet: any(named: 'wallet')))
            .thenAnswer((_) => Stream.fromIterable([0.0, 1.0]));
        await expectLater(
          turboUploader.upload(bundleHandle),
          emitsInOrder([0.0, 1.0, emitsDone]),
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
      when(() => turboBalanceRetriever.getBalanceAndPaidBy(any())).thenAnswer(
          (_) async =>
              TurboBalanceInterface(paidBy: [], balance: BigInt.from(500)));
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

    /// Tests for `getUploadPaymentInfo`
    ///
    group('getUploadPaymentInfo', () {
      late MockBundleUploadHandle mockBundle;
      late MockFileDataItemUploadHandle mockFile;
      late MockFileDataItemUploadHandle mockFile2;

      setUp(() {
        mockBundle = MockBundleUploadHandle();
        mockFile = MockFileDataItemUploadHandle();
        mockFile2 = MockFileDataItemUploadHandle();

        when(() => mockBundle.fileDataItemUploadHandles).thenReturn([
          mockFile,
          mockFile2,
        ]);

        when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);
      });

      /// Tests `isFreeUploadPossibleUsingTurbo`
      /// This is a special case where the user has enough balance to upload
      /// using turbo but the file size is small enough to be uploaded for free
      ///

      group('testing free uploads logic', () {
        setUp(() {
          when(() => uploadPlan.fileV2UploadHandles).thenReturn({});
        });
        test(
            'isFreeUploadPossibleUsingTurbo returns true when all file sizes are within turbo threshold',
            () async {
          when(() => mockFile.size).thenReturn(499);
          when(() => mockFile2.size).thenReturn(498);

          // limit of 500
          when(() => mockBundle.computeBundleSize())
              .thenAnswer((invocation) => Future.value(499));
          when(() => mockBundle.computeBundleSize())
              .thenAnswer((invocation) => Future.value(498));

          when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);

          final result =
              await uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          );

          expect(result.isFreeUploadPossibleUsingTurbo, isTrue);
          expect(result.isUploadEligibleToTurbo, isTrue);
        });
        test(
            'isFreeUploadPossibleUsingTurbo returns true when all file sizes are THE SAME turbo threshold',
            () async {
          when(() => mockFile.size).thenReturn(500);
          when(() => mockFile2.size).thenReturn(500);

          // limit of 500
          when(() => mockBundle.computeBundleSize())
              .thenAnswer((invocation) => Future.value(500));

          when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);

          final result =
              await uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          );

          expect(result.isFreeUploadPossibleUsingTurbo, isTrue);
          expect(result.isUploadEligibleToTurbo, isTrue);
        });
        test(
            'isFreeUploadPossibleUsingTurbo returns false when not all file sizes are within turbo threshold',
            () async {
          when(() => mockFile.size).thenReturn(501);
          // it tests that if one single file is bigger than 500, it should
          when(() => mockFile2.size).thenReturn(499);

          // limit of 500
          when(() => mockBundle.computeBundleSize())
              .thenAnswer((invocation) => Future.value(501));

          when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);

          final result =
              await uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          );

          expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
          expect(result.isUploadEligibleToTurbo, isTrue);
        });
        test(
            'isFreeUploadPossibleUsingTurbo returns false when having a single v2 file',
            () async {
          // bundle mock
          when(() => mockFile.size).thenReturn(499);
          // it tests that if one single file is bigger than 500, it should
          when(() => mockFile2.size).thenReturn(499);
          // limit of 500
          when(() => mockBundle.computeBundleSize())
              .thenAnswer((invocation) => Future.value(499));
          when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);

          // v2 file mock
          final mockV2Upload = MockFileV2UploadHandle();
          when(() => mockV2Upload.getFileDataSize()).thenReturn(501);
          when(() => mockV2Upload.getMetadataJSONSize()).thenReturn(0);
          when(() => uploadPlan.fileV2UploadHandles).thenReturn({
            'fileId': mockV2Upload,
          });
          when(() => mockV2Upload.size).thenReturn(501);

          final result =
              await uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          );

          expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
          expect(result.isUploadEligibleToTurbo, isFalse);
        });
      });

      /// Tests `isTurboAvailable`
      ///
      group('testing turbo eligibility', () {
        setUp(() {
          when(() => uploadPlan.fileV2UploadHandles).thenReturn({});
        });
        test('isUploadEligibleToTurbo returns true when have bundles',
            () async {
          when(() => mockFile.size).thenReturn(503);
          when(() => mockFile2.size).thenReturn(503);

          // limit of 500
          when(() => mockBundle.computeBundleSize())
              .thenAnswer((invocation) => Future.value(503));

          when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);

          final result =
              await uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          );

          expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
          expect(result.isUploadEligibleToTurbo, isTrue);
        });

        test('isTurboUploadPossible returns false when not have any bundles',
            () async {
          final mockFile = MockBundleUploadHandle();
          when(() => mockFile.size).thenReturn(501);
          // limit of 500
          when(() => mockFile.computeBundleSize())
              .thenAnswer((invocation) => Future.value(501));

          when(() => uploadPlan.bundleUploadHandles).thenReturn([]);

          final result =
              await uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          );

          expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
          expect(result.isUploadEligibleToTurbo, isFalse);
          expect(result.isTurboAvailable, isTrue);
        });

        test(
            'isTurboUploadPossible returns false when not have any bundles but have a v2',
            () async {
          final mockFile = MockBundleUploadHandle();
          when(() => mockFile.size).thenReturn(501);
          // limit of 500
          when(() => mockFile.computeBundleSize())
              .thenAnswer((invocation) => Future.value(501));

          // NO BUNDLES
          when(() => uploadPlan.bundleUploadHandles).thenReturn([]);

          // v2 file mock
          final mockV2Upload = MockFileV2UploadHandle();
          when(() => mockV2Upload.getFileDataSize()).thenReturn(501);
          when(() => mockV2Upload.getMetadataJSONSize()).thenReturn(0);
          when(() => mockV2Upload.size).thenReturn(501);

          // a V2
          when(() => uploadPlan.fileV2UploadHandles).thenReturn({
            'fileId': mockV2Upload,
          });

          final result =
              await uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          );

          expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
          expect(result.isUploadEligibleToTurbo, isFalse);
          expect(result.isTurboAvailable, isTrue);
        });

        test(
            'isTurboUploadPossible returns false when we have bundles but have at least one v2',
            () async {
          final mockFile = MockBundleUploadHandle();
          when(() => mockFile.size).thenReturn(501);
          // limit of 500
          when(() => mockFile.computeBundleSize())
              .thenAnswer((invocation) => Future.value(501));

          // NO BUNDLES
          when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);

          when(() => mockBundle.computeBundleSize())
              .thenAnswer((invocation) => Future.value(503));

          // v2 file mock
          final mockV2Upload = MockFileV2UploadHandle();
          when(() => mockV2Upload.getFileDataSize()).thenReturn(501);
          when(() => mockV2Upload.getMetadataJSONSize()).thenReturn(0);
          when(() => mockV2Upload.size).thenReturn(501);

          // a V2
          when(() => uploadPlan.fileV2UploadHandles).thenReturn({
            'fileId': mockV2Upload,
          });

          final result =
              await uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          );

          expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
          expect(result.isUploadEligibleToTurbo, isFalse);
          expect(result.isTurboAvailable, isTrue);
        });

        test('isTurboAvailable returns false when the feature flag is false',
            () async {
          final turboBalanceRetriever = MockTurboBalanceRetriever();
          final paymentEvaluatorWithFeatureFlagFalse = UploadPaymentEvaluator(
            turboBalanceRetriever: turboBalanceRetriever,
            uploadCostEstimateCalculatorForAR:
                uploadCostEstimateCalculatorForAR,
            auth: auth,
            turboUploadCostCalculator: turboUploadCostCalculator,
            appConfig: getFakeConfigForDisabledTurbo(),
          );

          when(() => mockFile.size).thenReturn(503);
          when(() => mockFile2.size).thenReturn(503);

          // limit of 500
          when(() => mockBundle.computeBundleSize())
              .thenAnswer((invocation) => Future.value(503));

          when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);

          final result = await paymentEvaluatorWithFeatureFlagFalse
              .getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          );

          expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
          expect(result.isUploadEligibleToTurbo, isTrue);
          expect(result.isTurboAvailable, isFalse);

          verifyNever(() => turboBalanceRetriever.getBalance(any()));
        });

        test('isTurboAvailable returns false when getBalance throws', () async {
          when(() => mockFile.size).thenReturn(501);
          when(() => mockBundle.computeBundleSize())
              .thenAnswer((invocation) => Future.value(501));
          when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);
          when(() => turboBalanceRetriever.getBalanceAndPaidBy(any()))
              .thenThrow(Exception('error'));

          final result =
              await uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          );

          // the important part is that we don't throw
          expect(result.isTurboAvailable, isFalse);

          expect(result.isFreeUploadPossibleUsingTurbo, isFalse);

          // To be eligible to turbo, we just need to pass a bundle
          expect(result.isUploadEligibleToTurbo, isTrue);

          // the payment method must be AR
          expect(result.defaultPaymentMethod, equals(UploadMethod.ar));
        });

        test('isTurboAvailable returns false when calculateCost throws',
            () async {
          when(() => mockFile.size).thenReturn(501);
          when(() => mockBundle.computeBundleSize())
              .thenAnswer((invocation) => Future.value(501));
          when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);
          when(() => turboUploadCostCalculator.calculateCost(
              totalSize: any(named: 'totalSize'))).thenThrow(Exception());

          final result =
              await uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          );

          // the important part is that we don't throw
          expect(result.isTurboAvailable, isFalse);
          expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
          expect(result.isUploadEligibleToTurbo, isTrue);

          // the payment method must be AR
          expect(result.defaultPaymentMethod, equals(UploadMethod.ar));
        });
      });

      group('testing the result', () {
        setUp(() {
          mockBundle = MockBundleUploadHandle();
          mockFile = MockFileDataItemUploadHandle();
          mockFile2 = MockFileDataItemUploadHandle();

          when(() => mockBundle.fileDataItemUploadHandles).thenReturn([
            mockFile,
            mockFile2,
          ]);

          when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);

          when(() => mockFile.size).thenReturn(501);

          // limit of 500
          when(() => mockBundle.computeBundleSize())
              .thenAnswer((invocation) => Future.value(499));
        });
        test(
            'getUploadPaymentInfo assigns UploadMethod.turbo when turbo balance is enough',
            () async {
          // 400 total cost
          final mockUploadCostEstimateTurbo = UploadCostEstimate(
            totalCost: BigInt.from(400),
            pstFee: BigInt.from(40),
            totalSize: 1000,
            usdUploadCost: 100,
          );

          when(() => uploadCostEstimateCalculatorForAR.calculateCost(
                  totalSize: any(named: 'totalSize')))
              .thenAnswer((_) async => mockUploadCostEstimateAR);
          when(() => turboUploadCostCalculator.calculateCost(
                  totalSize: any(named: 'totalSize')))
              .thenAnswer((_) async => mockUploadCostEstimateTurbo);

          // balance 100
          when(() => turboBalanceRetriever.getBalance(any()))
              .thenAnswer((_) async => BigInt.from(500));

          final result =
              await uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          );

          expect(result.defaultPaymentMethod, equals(UploadMethod.turbo));
          expect(result.isUploadEligibleToTurbo, isTrue);
          expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
        });
        test(
            'getUploadPaymentInfo assigns UploadMethod.ar when turbo balance is not enough',
            () async {
          when(() => sizeUtils.getSizeOfAllBundles(any()))
              .thenAnswer((_) async => 200);
          when(() => sizeUtils.getSizeOfAllV2Files(any()))
              .thenAnswer((_) async => 200);

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

          final mockFile = MockBundleUploadHandle();

          // limit of 500
          when(() => mockFile.computeBundleSize())
              .thenAnswer((invocation) => Future.value(501));

          when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);

          when(() => mockBundle.computeBundleSize())
              .thenAnswer((invocation) => Future.value(501));

          final result =
              await uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          );

          expect(result.defaultPaymentMethod, equals(UploadMethod.ar));
          expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
        });

        test('returns the expected UploadPaymentInfo', () async {
          when(() => uploadCostEstimateCalculatorForAR.calculateCost(
                  totalSize: any(named: 'totalSize')))
              .thenAnswer((_) async => mockUploadCostEstimateAR);
          when(() => turboUploadCostCalculator.calculateCost(
                  totalSize: any(named: 'totalSize')))
              .thenAnswer((_) async => mockUploadCostEstimateTurbo);

          when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);
          when(() => turboBalanceRetriever.getBalance(any()))
              .thenAnswer((_) async => BigInt.from(500));

          final result =
              await uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          );

          expect(result.arCostEstimate, mockUploadCostEstimateAR);
          expect(result.turboCostEstimate, mockUploadCostEstimateTurbo);
          expect(result.defaultPaymentMethod, equals(UploadMethod.turbo));
          expect(result.isUploadEligibleToTurbo, isTrue);
          expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
        });

        test('returns the expected UploadPaymentInfo', () async {
          when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);
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

          when(() => uploadCostEstimateCalculatorForAR.calculateCost(
                  totalSize: any(named: 'totalSize')))
              .thenAnswer((_) async => mockUploadCostEstimateAR);
          when(() => turboUploadCostCalculator.calculateCost(
                  totalSize: any(named: 'totalSize')))
              .thenAnswer((_) async => mockUploadCostEstimateTurbo);
          when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);
          when(() => uploadPlan.bundleUploadHandles).thenReturn([mockBundle]);
          when(() => mockBundle.computeBundleSize())
              .thenAnswer((invocation) => Future.value(501));
          when(() => mockFile.size).thenReturn(501);

          final result =
              await uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: uploadPlan,
            uploadPlanForTurbo: uploadPlan,
          );

          expect(result.arCostEstimate, mockUploadCostEstimateAR);
          expect(result.turboCostEstimate, mockUploadCostEstimateTurbo);
          expect(result.defaultPaymentMethod, equals(UploadMethod.ar));
          expect(result.isUploadEligibleToTurbo, isTrue);
          expect(result.isFreeUploadPossibleUsingTurbo, isFalse);
        });
      });
    });
  });

  group('UploadPreparer', () {
    late UploadPreparer uploadPreparer;
    late UploadPlanUtils uploadPlanUtils;
    late UploadParams uploadParams;

    setUpAll(() {
      registerFallbackValue(SecretKey([]));
      registerFallbackValue(UploadParams(
          user: getFakeUser(),
          files: [],
          targetFolder: getFakeFolder(),
          targetDrive: getFakeDrive(),
          conflictingFiles: {},
          foldersByPath: {},
          containsSupportedImageTypeForThumbnailGeneration: false,
          paidBy: []));
      registerFallbackValue(getFakeFolder());
      registerFallbackValue(getFakeDrive());
      registerFallbackValue(getFakeUser());
      registerFallbackValue(getTestWallet());
    });

    setUp(() {
      uploadPlanUtils = MockUploadPlanUtils();
      uploadParams = UploadParams(
          user: getFakeUser(),
          files: [],
          targetFolder: getFakeFolder(),
          targetDrive: getFakeDrive(),
          conflictingFiles: {},
          foldersByPath: {},
          containsSupportedImageTypeForThumbnailGeneration: false,
          paidBy: []);
      uploadPreparer = UploadPreparer(uploadPlanUtils: uploadPlanUtils);
    });

    test('Should prepare AR and Turbo upload plans', () async {
      final uploadPlan = MockUploadPlan();

      when(() => uploadPlanUtils.filesToUploadPlan(
            cipherKey: any(named: 'cipherKey'),
            files: any(named: 'files'),
            targetFolder: any(named: 'targetFolder'),
            targetDrive: any(named: 'targetDrive'),
            foldersByPath: any(named: 'foldersByPath'),
            conflictingFiles: any(named: 'conflictingFiles'),
            wallet: any(named: 'wallet'),
            useTurbo: any(named: 'useTurbo'),
          )).thenAnswer((_) async => uploadPlan);

      // Act
      final result = await uploadPreparer.prepareFileUpload(uploadParams);

      // Assert
      expect(result.uploadPlanForAr, uploadPlan);
      expect(result.uploadPlanForTurbo, uploadPlan);
      verify(() => uploadPlanUtils.filesToUploadPlan(
                cipherKey: any(named: 'cipherKey'),
                files: any(named: 'files'),
                targetFolder: any(named: 'targetFolder'),
                targetDrive: any(named: 'targetDrive'),
                foldersByPath: any(named: 'foldersByPath'),
                conflictingFiles: any(named: 'conflictingFiles'),
                wallet: any(named: 'wallet'),
                useTurbo: any(named: 'useTurbo'),
              ))
          .called(
              2); // Method should be called twice, one for each upload method.
    });

    test('Should throw if preparing AR plan fails', () async {
      when(() => uploadPlanUtils.filesToUploadPlan(
            cipherKey: any(named: 'cipherKey'),
            files: any(named: 'files'),
            targetFolder: any(named: 'targetFolder'),
            targetDrive: any(named: 'targetDrive'),
            foldersByPath: any(named: 'foldersByPath'),
            conflictingFiles: any(named: 'conflictingFiles'),
            wallet: any(named: 'wallet'),
            useTurbo: any(named: 'useTurbo'),
          )).thenThrow(Exception());

      // Assert
      expectLater(() => uploadPreparer.prepareFileUpload(uploadParams),
          throwsA(isA<Exception>()));
    });

    test('Should throw if preparing Turbo plan fails', () async {
      // TODO: tech debt
    });
  });

  group('ArDriveUploadPreparationManager', () {
    final uploadPlan = MockUploadPlan();

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

    late ArDriveUploadPreparationManager uploadPreparationManager;
    late UploadPreparer uploadPreparer;
    late UploadPaymentEvaluator uploadPaymentEvaluator;
    late UploadParams uploadParams;

    setUpAll(() {
      uploadPreparer = MockUploadPreparer();
      uploadPaymentEvaluator = MockUploadPaymentEvaluator();
      uploadParams = MockUploadParams();
      uploadPreparationManager = ArDriveUploadPreparationManager(
        uploadPreparer: uploadPreparer,
        uploadPreparePaymentOptions: uploadPaymentEvaluator,
      );
      registerFallbackValue(MockUploadPlan());

      registerFallbackValue(UploadParams(
          user: getFakeUser(),
          files: [],
          targetFolder: getFakeFolder(),
          targetDrive: getFakeDrive(),
          conflictingFiles: {},
          foldersByPath: {},
          containsSupportedImageTypeForThumbnailGeneration: false,
          paidBy: []));
    });

    group('prepareUpload', () {
      test('Should prepare upload and compute payment info', () async {
        // Arrange
        final uploadPlansPreparation = UploadPlansPreparation(
          uploadPlanForAr: uploadPlan,
          uploadPlanForTurbo: uploadPlan,
        );

        final uploadPaymentInfo = UploadPaymentInfo(
          defaultPaymentMethod: UploadMethod.ar,
          isUploadEligibleToTurbo: true,
          arCostEstimate: mockUploadCostEstimateAR,
          turboCostEstimate: mockUploadCostEstimateTurbo,
          isFreeUploadPossibleUsingTurbo: true,
          totalSize: 100,
          isTurboAvailable: true,
          turboBalance:
              TurboBalanceInterface(balance: BigInt.from(500), paidBy: []),
        );

        when(() => uploadPreparer.prepareFileUpload(uploadParams))
            .thenAnswer((_) async => uploadPlansPreparation);
        when(() => uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
                uploadPlanForAR: uploadPlan, uploadPlanForTurbo: uploadPlan))
            .thenAnswer((_) async => uploadPaymentInfo);

        // Act
        final result =
            await uploadPreparationManager.prepareUpload(params: uploadParams);

        // Assert
        expect(result.uploadPlansPreparation, uploadPlansPreparation);
        expect(result.uploadPaymentInfo, uploadPaymentInfo);
        verify(() => uploadPreparer.prepareFileUpload(any())).called(1);
        verify(() => uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
            uploadPlanForAR: any(named: 'uploadPlanForAR'),
            uploadPlanForTurbo: any(named: 'uploadPlanForTurbo'))).called(1);
      });

      test('Should throw if preparing upload plans fails', () async {
        // Arrange
        when(() => uploadPreparer.prepareFileUpload(any()))
            .thenThrow(Exception('Failed to prepare upload plans'));

        // Act
        final call =
            uploadPreparationManager.prepareUpload(params: uploadParams);

        // Assert
        expect(() async => await call, throwsA(isA<Exception>()));
      });

      test('Should throw if upload prepartion fails', () async {
        when(() => uploadPreparer.prepareFileUpload(uploadParams))
            .thenThrow(Exception('Failed to prepare upload plans'));

        final call =
            uploadPreparationManager.prepareUpload(params: uploadParams);

        // Assert
        expect(() async => await call, throwsA(isA<Exception>()));
      });

      test('Should throw if getting upload payment info fails', () async {
        // Arrange
        final uploadPlansPreparation = UploadPlansPreparation(
          uploadPlanForAr: uploadPlan,
          uploadPlanForTurbo: uploadPlan,
        );

        when(() => uploadPreparer.prepareFileUpload(uploadParams))
            .thenAnswer((_) async => uploadPlansPreparation);
        when(() => uploadPaymentEvaluator.getUploadPaymentInfoForUploadPlans(
                uploadPlanForAR: uploadPlan, uploadPlanForTurbo: uploadPlan))
            .thenThrow(Exception('Failed to get upload payment info'));

        // Act
        final call =
            uploadPreparationManager.prepareUpload(params: uploadParams);

        // Assert
        expect(() async => await call, throwsA(isA<Exception>()));
      });
    });
  });
}

AppConfig getFakeConfig() => AppConfig(
      allowedDataItemSizeForTurbo: 500,
      stripePublishableKey: '',
      useTurboUpload: true,
      useTurboPayment: true,
      defaultArweaveGatewayForDataRequest: const SelectedGateway(
        label: 'ArDrive Turbo Gateway',
        url: 'https://ardrive.net',
      ),
    );

AppConfig getFakeConfigForDisabledTurbo() => AppConfig(
      allowedDataItemSizeForTurbo: 500,
      stripePublishableKey: '',
      useTurboUpload: false,
      useTurboPayment: false,
      defaultArweaveGatewayForDataRequest: const SelectedGateway(
        label: 'ArDrive Turbo Gateway',
        url: 'https://ardrive.net',
      ),
    );
User getFakeUser() => User(
      password: 'password',
      wallet: getTestWallet(),
      walletAddress: 'walletAddress',
      walletBalance: BigInt.one,
      cipherKey: SecretKey([]),
      profileType: ProfileType.arConnect,
      errorFetchingIOTokens: false,
    );

FolderEntry getFakeFolder() => FolderEntry(
      id: 'id',
      driveId: 'drive id',
      name: 'name',
      dateCreated: DateTime.now(),
      lastUpdated: DateTime.now(),
      isGhost: false,
      isHidden: false,
      path: '',
    );

Drive getFakeDrive() => Drive(
      id: 'id',
      name: 'name',
      dateCreated: DateTime.now(),
      lastUpdated: DateTime.now(),
      rootFolderId: 'rootFolderId',
      ownerAddress: 'ownerAddress',
      privacy: 'privacy',
      isHidden: false,
    );
