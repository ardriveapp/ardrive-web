import 'package:ardrive/blocs/upload/upload_handles/handles.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/services/turbo/upload_service.dart';
import 'package:arweave/arweave.dart';
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
}
