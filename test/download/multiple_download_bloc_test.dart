import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/download/multiple_download_bloc.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:ardrive/utils/data_size.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  DriveDao mockDriveDao = MockDriveDao();
  ArweaveService mockArweaveService = MockArweaveService();
  ArDriveCrypto mockCrypto = MockArDriveCrypto();
  DownloadService mockDownloadService = MockDownloadService();
  ARFSRepository mockARFSRepository = MockARFSRepository();
  ARFSRepository mockARFSRepositoryPrivate = MockARFSRepository();

  MockARFSFile testFile = createMockFile(size: const MiB(1).size);

  MockARFSDrive mockDrivePrivate =
      createMockDrive(drivePrivacy: DrivePrivacy.private);

  MockARFSDrive mockDrivePublic =
      createMockDrive(drivePrivacy: DrivePrivacy.public);

  MockTransactionCommonMixin decryptionFailureTransaction =
      MockTransactionCommonMixin();

  MultipleDownloadBloc createMultipleDownloadBloc(
      {downloadService,
      arfsRepository,
      arweave,
      crypto,
      driveDao,
      cipherKey,
      deviceInfo}) {
    return MultipleDownloadBloc(
        downloadService: downloadService ?? mockDownloadService,
        arfsRepository: arfsRepository ?? mockARFSRepository,
        arweave: arweave ?? mockArweaveService,
        crypto: crypto ?? mockCrypto,
        driveDao: driveDao ?? mockDriveDao,
        cipherKey: cipherKey ?? SecretKey([]),
        deviceInfo: deviceInfo);
  }

  setUpAll(() {
    registerFallbackValue(SecretKey([]));
    registerFallbackValue(MockTransactionCommonMixin());
    registerFallbackValue(Uint8List(100));
    registerFallbackValue(mockDrivePrivate);
    registerFallbackValue(mockDrivePublic);
    registerFallbackValue(testFile);
  });

  setUp(() {
    /// Using a private drive
    when(() => mockARFSRepository.getDriveById(any()))
        .thenAnswer((_) async => mockDrivePublic);
    when(() => mockARFSRepositoryPrivate.getDriveById(any()))
        .thenAnswer((_) async => mockDrivePrivate);
    when(() => mockDriveDao.getDriveKey(any(), any()))
        .thenAnswer((_) async => SecretKey([]));
    when(() => mockDriveDao.getFileKey(any(), any()))
        .thenAnswer((_) async => SecretKey([]));
    when(() => mockDownloadService.download(any()))
        .thenAnswer((_) async => Uint8List(0));
    when(() => mockCrypto.decryptTransactionData(any(), any(), any()))
        .thenAnswer((_) async => Uint8List(0));
    when(() => mockCrypto.decryptTransactionData(
        decryptionFailureTransaction, any(), any())).thenThrow(Exception());
    when(() => mockArweaveService.getTransactionDetails(any()))
        .thenAnswer((invocation) async => MockTransactionCommonMixin());
    when(() => mockArweaveService.getTransactionDetails('decryptionFailure'))
        .thenAnswer((invocation) async => decryptionFailureTransaction);
    when(() => mockArweaveService.getTransactionDetails(''))
        .thenAnswer((invocation) async => null);
  });

  void performTestsForDrive(String groupLabel, ARFSRepository arfsRepository) {
    late MultipleDownloadBloc multipleDownloadBloc;
    group('[$groupLabel] -', () {
      setUp(() {
        multipleDownloadBloc = createMultipleDownloadBloc(
          arfsRepository: arfsRepository,
        );
      });

      group('Test file limits', () {
        blocTest<MultipleDownloadBloc, MultipleDownloadState>(
          'should succeed with files below limits',
          build: () => multipleDownloadBloc,
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Android);
          },
          act: (bloc) => bloc.add(StartDownload([testFile])),
          expect: () => [
            isA<MultipleDownloadInProgress>().having(
              (s) => s.files.length,
              'files.length',
              1,
            ),
            isA<MultipleDownloadFinishedWithSuccess>()
                .having((s) => s.skippedFiles.length, 'skippedFiles.length', 0),
          ],
        );

        blocTest<MultipleDownloadBloc, MultipleDownloadState>(
          'should emit failure when files above limits (Android)',
          build: createMultipleDownloadBloc,
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Android);
          },
          act: (bloc) => bloc.add(StartDownload([
            testFile,
            createMockFile(size: const MiB(2001).size),
          ])),
          expect: () => [
            isA<MultipleDownloadFailure>().having(
              (s) => s.reason,
              'reason',
              FileDownloadFailureReason.fileAboveLimit,
            ),
          ],
        );

        blocTest<MultipleDownloadBloc, MultipleDownloadState>(
          'should emit failure when files above limits (Chrome)',
          build: () {
            final MockDeviceInfoPlugin deviceInfo = MockDeviceInfoPlugin();

            when(() => deviceInfo.deviceInfo).thenAnswer((invokation) async =>
                WebBrowserInfo.fromMap({'userAgent': 'Chrome'}));

            return createMultipleDownloadBloc(deviceInfo: deviceInfo);
          },
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Web);
          },
          act: (bloc) => bloc.add(StartDownload([
            testFile,
            createMockFile(size: const MiB(501).size),
          ])),
          expect: () => [
            isA<MultipleDownloadFailure>().having(
              (s) => s.reason,
              'reason',
              FileDownloadFailureReason.fileAboveLimit,
            ),
          ],
        );

        blocTest<MultipleDownloadBloc, MultipleDownloadState>(
          'should emit failure when files above limits (Firefox)',
          build: () {
            final MockDeviceInfoPlugin deviceInfo = MockDeviceInfoPlugin();

            when(() => deviceInfo.deviceInfo).thenAnswer((invocation) async =>
                WebBrowserInfo.fromMap({'userAgent': 'Firefox'}));

            return createMultipleDownloadBloc(deviceInfo: deviceInfo);
          },
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Web);
          },
          act: (bloc) => bloc.add(StartDownload([
            testFile,
            createMockFile(size: const GiB(2).size),
          ])),
          expect: () => [
            isA<MultipleDownloadFailure>().having(
              (s) => s.reason,
              'reason',
              FileDownloadFailureReason.fileAboveLimit,
            ),
          ],
        );
      });
      group('Test successful download path', () {
        blocTest<MultipleDownloadBloc, MultipleDownloadState>(
          'should emit one MultipleDownloadInProgress event per file',
          build: () => multipleDownloadBloc,
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Android);
          },
          act: (bloc) =>
              bloc.add(StartDownload([testFile, testFile, testFile])),
          expect: () => [
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 0),
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 1),
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 2),
            isA<MultipleDownloadFinishedWithSuccess>()
                .having((s) => s.skippedFiles.length, 'skippedFiles.length', 0),
          ],
        );
      });

      group('Test networking', () {
        blocTest<MultipleDownloadBloc, MultipleDownloadState>(
          'should emit Failure with fileNotFound when file is not available',
          build: () {
            final secondFileFailureService = MockDownloadService();
            when(() => secondFileFailureService.download(any()))
                .thenAnswer((_) async => Uint8List(0));
            when(() => secondFileFailureService.download("fail")).thenThrow(
                ArDriveHTTPException(
                    exception: Exception(),
                    retryAttempts: 8,
                    statusCode: 400,
                    statusMessage: 'File not found'));
            return createMultipleDownloadBloc(
                downloadService: secondFileFailureService);
          },
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Android);
          },
          act: (bloc) => bloc.add(StartDownload(
              [testFile, createMockFile(txId: 'fail'), testFile])),
          expect: () => [
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 0),
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 1),
            isA<MultipleDownloadFailure>().having((s) => s.reason, 'reason',
                FileDownloadFailureReason.fileNotFound),
          ],
        );

        blocTest<MultipleDownloadBloc, MultipleDownloadState>(
          'should emit Failure with networkConnectionError when status code is not 400',
          build: () {
            final secondFileFailureService = MockDownloadService();
            when(() => secondFileFailureService.download(any()))
                .thenAnswer((_) async => Uint8List(0));
            when(() => secondFileFailureService.download("fail")).thenThrow(
                ArDriveHTTPException(
                    exception: Exception(),
                    retryAttempts: 8,
                    statusCode: 404,
                    statusMessage: 'File not found'));
            return createMultipleDownloadBloc(
                downloadService: secondFileFailureService);
          },
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Android);
          },
          act: (bloc) => bloc.add(StartDownload(
              [testFile, createMockFile(txId: 'fail'), testFile])),
          expect: () => [
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 0),
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 1),
            isA<MultipleDownloadFailure>().having((s) => s.reason, 'reason',
                FileDownloadFailureReason.networkConnectionError),
          ],
        );

        blocTest<MultipleDownloadBloc, MultipleDownloadState>(
          'should emit Failure with networkConnectionError when status code is not 400 and resumes correctly',
          build: () {
            var failedOnce = false;
            final secondFileFailureService = MockDownloadService();
            when(() => secondFileFailureService.download(any()))
                .thenAnswer((_) async => Uint8List(0));
            when(() => secondFileFailureService.download("fail"))
                .thenAnswer((_) async {
              if (!failedOnce) {
                failedOnce = true;
                throw ArDriveHTTPException(
                    exception: Exception(),
                    retryAttempts: 8,
                    statusCode: 404,
                    statusMessage: 'File not found');
              }
              return Uint8List(0);
            });

            return createMultipleDownloadBloc(
                downloadService: secondFileFailureService);
          },
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Android);
          },
          act: (bloc) async {
            bloc.add(StartDownload(
                [testFile, createMockFile(txId: 'fail'), testFile]));

            // TODO: Replace this polling with a better solution!
            while (bloc.state is! MultipleDownloadFailure) {
              await Future.delayed(const Duration(milliseconds: 100));
            }

            bloc.add(const ResumeDownload());
          },
          expect: () => [
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 0),
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 1),
            isA<MultipleDownloadFailure>().having((s) => s.reason, 'reason',
                FileDownloadFailureReason.networkConnectionError),
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 1),
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 2),
            isA<MultipleDownloadFinishedWithSuccess>()
                .having((s) => s.skippedFiles.length, 'skippedFiles.length', 0),
          ],
        );

        blocTest<MultipleDownloadBloc, MultipleDownloadState>(
          'should emit Failure with networkConnectionError when status code is not 400 and skips files correctly',
          build: () {
            var failedOnce = false;
            final secondFileFailureService = MockDownloadService();
            when(() => secondFileFailureService.download(any()))
                .thenAnswer((_) async => Uint8List(0));
            when(() => secondFileFailureService.download("fail"))
                .thenAnswer((_) async {
              if (!failedOnce) {
                failedOnce = true;
                throw ArDriveHTTPException(
                    exception: Exception(),
                    retryAttempts: 8,
                    statusCode: 404,
                    statusMessage: 'File not found');
              }
              return Uint8List(0);
            });

            return createMultipleDownloadBloc(
                downloadService: secondFileFailureService);
          },
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Android);
          },
          act: (bloc) async {
            bloc.add(StartDownload(
                [testFile, createMockFile(txId: 'fail'), testFile]));

            // TODO: Replace this polling with a better solution!
            while (bloc.state is! MultipleDownloadFailure) {
              await Future.delayed(const Duration(milliseconds: 100));
            }

            bloc.add(const SkipFileAndResumeDownload());
          },
          expect: () => [
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 0),
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 1),
            isA<MultipleDownloadFailure>().having((s) => s.reason, 'reason',
                FileDownloadFailureReason.networkConnectionError),
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 2),
            isA<MultipleDownloadFinishedWithSuccess>()
                .having((s) => s.skippedFiles.length, 'skippedFiles.length', 1)
                .having(
                    (s) =>
                        s.skippedFiles.isNotEmpty ? s.skippedFiles[0].txId : '',
                    'skippedFile txid',
                    'fail'),
          ],
        );
      });
      group('Test cancelation path', () {
        blocTest<MultipleDownloadBloc, MultipleDownloadState>(
          'should end Bloc after cancellation',
          build: () {
            final secondFileCancelService = MockDownloadService();
            when(() => secondFileCancelService.download(any()))
                .thenAnswer((_) async => Uint8List(0));

            final bloc = createMultipleDownloadBloc(
                downloadService: secondFileCancelService);

            when(() => secondFileCancelService.download('cancel'))
                .thenAnswer((_) async {
              bloc.add(const CancelDownload());
              return Uint8List(0);
            });

            return bloc;
          },
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Android);
          },
          act: (bloc) => bloc.add(StartDownload(
              [testFile, createMockFile(txId: 'cancel'), testFile])),
          expect: () => [
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 0),
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  3,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 1),
          ],
        );
      });

      if (arfsRepository == mockARFSRepositoryPrivate) {
        blocTest<MultipleDownloadBloc, MultipleDownloadState>(
          'Test missing transactionDetails should emit failure',
          build: () => multipleDownloadBloc,
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Android);
          },
          act: (bloc) => bloc.add(StartDownload(
              [testFile, testFile, createMockFile(txId: ''), testFile])),
          expect: () => [
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  4,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 0),
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  4,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 1),
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  4,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 2),
            isA<MultipleDownloadFailure>().having((s) => s.reason, 'reason',
                FileDownloadFailureReason.unknownError),
          ],
        );
        blocTest<MultipleDownloadBloc, MultipleDownloadState>(
          'Test decryption failure should emit failure',
          build: () => multipleDownloadBloc,
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Android);
          },
          act: (bloc) => bloc.add(StartDownload([
            testFile,
            testFile,
            createMockFile(txId: 'decryptionFailure'),
            testFile
          ])),
          expect: () => [
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  4,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 0),
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  4,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 1),
            isA<MultipleDownloadInProgress>()
                .having(
                  (s) => s.files.length,
                  'files.length',
                  4,
                )
                .having((s) => s.currentFileIndex, 'currentFileIndex', 2),
            isA<MultipleDownloadFailure>().having((s) => s.reason, 'reason',
                FileDownloadFailureReason.unknownError),
          ],
        );
      }
    });
  }

  performTestsForDrive('Public Drive', mockARFSRepository);
  performTestsForDrive('Private Drive', mockARFSRepositoryPrivate);
}
