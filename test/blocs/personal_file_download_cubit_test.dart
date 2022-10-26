import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/core/decrypt.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:ardrive/utils/data_size.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

class MockARFSFile extends ARFSFileEntity {
  MockARFSFile({
    required super.appName,
    required super.appVersion,
    required super.arFS,
    required super.driveId,
    required super.entityType,
    required super.name,
    required super.txId,
    required super.unixTime,
    required super.id,
    required super.size,
    required super.lastModifiedDate,
    required super.parentFolderId,
    super.contentType,
  });
}

class MockARFSDrive extends ARFSDriveEntity {
  MockARFSDrive({
    required super.appName,
    required super.appVersion,
    required super.arFS,
    required super.driveId,
    required super.entityType,
    required super.name,
    required super.txId,
    required super.unixTime,
    required super.drivePrivacy,
    required super.rootFolderId,
  });
}

Stream<int> mockDownloadProgress() async* {
  yield 100;
}

Stream<int> mockDownloadInProgress() {
  return Stream<int>.periodic(const Duration(seconds: 1), (c) => c + 1).take(5);
}

class MockTransactionCommonMixin extends Mock
    implements TransactionCommonMixin {}

// TODO(@thiagocarvalhodev): Implemente tests related to ArDriveDownloader
void main() {
  late ProfileFileDownloadCubit profileFileDownloadCubit;
  late DriveDao mockDriveDao;
  late ArweaveService mockArweaveService;
  late ArDriveDownloader mockArDriveDownloader;
  late Decrypt mockDecrypt;
  late DownloadService mockDownloadService;
  late ARFSRepository mockARFSRepository;

  MockARFSFile testFile = MockARFSFile(
    appName: 'appName',
    appVersion: 'appVersion',
    arFS: 'arFS',
    driveId: 'driveId',
    entityType: EntityType.file,
    name: 'name',
    txId: 'txId',
    unixTime: DateTime.now(),
    id: 'id',
    size: const MiB(2).size,
    lastModifiedDate: DateTime.now(),
    parentFolderId: 'parentFolderId',
    contentType: 'text/plain',
  );

  MockARFSFile testFileAboveLimit = MockARFSFile(
    appName: 'appName',
    appVersion: 'appVersion',
    arFS: 'arFS',
    driveId: 'driveId',
    entityType: EntityType.file,
    name: 'name',
    txId: 'txId',
    unixTime: DateTime.now(),
    id: 'id',
    size: const MiB(301).size, // above the current limit
    lastModifiedDate: DateTime.now(),
    parentFolderId: 'parentFolderId',
    contentType: 'text/plain',
  );

  MockARFSFile testFileUnderPrivateLimitAndAboveWarningLimit = MockARFSFile(
    appName: 'appName',
    appVersion: 'appVersion',
    arFS: 'arFS',
    driveId: 'driveId',
    entityType: EntityType.file,
    name: 'name',
    txId: 'txId',
    unixTime: DateTime.now(),
    id: 'id',
    size: const MiB(201).size, // above the current limit
    lastModifiedDate: DateTime.now(),
    parentFolderId: 'parentFolderId',
    contentType: 'text/plain',
  );

  MockARFSDrive mockDrivePrivate = MockARFSDrive(
    appName: 'appName',
    appVersion: 'appVersion',
    arFS: 'arFS',
    driveId: '',
    entityType: EntityType.drive,
    name: 'name',
    txId: 'txId',
    unixTime: DateTime.now(),
    drivePrivacy: DrivePrivacy.private,
    rootFolderId: 'rootFolderId',
  );

  MockARFSDrive mockDrivePublic = MockARFSDrive(
    appName: 'appName',
    appVersion: 'appVersion',
    arFS: 'arFS',
    driveId: '',
    entityType: EntityType.drive,
    name: 'name',
    txId: 'txId',
    unixTime: DateTime.now(),
    drivePrivacy: DrivePrivacy.public,
    rootFolderId: 'rootFolderId',
  );

  setUpAll(() {
    registerFallbackValue(SecretKey([]));
    registerFallbackValue(MockTransactionCommonMixin());
    registerFallbackValue(Uint8List(100));
    registerFallbackValue(mockDrivePrivate);
    registerFallbackValue(mockDrivePublic);
    registerFallbackValue(testFile);
    registerFallbackValue(mockDownloadProgress());
    registerFallbackValue(mockDownloadInProgress());
  });

  setUp(() {
    mockDriveDao = MockDriveDao();
    mockArweaveService = MockArweaveService();
    mockArDriveDownloader = MockArDriveDownloader();
    mockDecrypt = MockDecrypt();
    mockDownloadService = MockDownloadService();
    mockARFSRepository = MockARFSRepository();
  });

  group('Testing isFileAboveLimit method', () {
    setUp(() {
      profileFileDownloadCubit = ProfileFileDownloadCubit(
        file: testFile,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
      );
    });
    test('should return false', () {
      expect(
          profileFileDownloadCubit.isSizeAbovePrivateLimit(const MiB(1).size),
          false);
    });
    test('should return false', () {
      expect(
          profileFileDownloadCubit.isSizeAbovePrivateLimit(const MiB(299).size),
          false);
    });

    test('should return true', () {
      expect(
          profileFileDownloadCubit.isSizeAbovePrivateLimit(const MiB(300).size),
          false);
    });

    test('should return true', () {
      expect(
          profileFileDownloadCubit.isSizeAbovePrivateLimit(const MiB(301).size),
          true);
    });

    test('should return true', () {
      expect(
          profileFileDownloadCubit.isSizeAbovePrivateLimit(const GiB(1).size),
          true);
    });
  });

  group('Testing download method', () {
    setUp(() {
      when(() => mockARFSRepository.getDriveById(any()))
          .thenAnswer((_) async => mockDrivePrivate);
      when(() => mockDownloadService.download(any()))
          .thenAnswer((invocation) => Future.value(Uint8List(100)));
      when(() => mockDriveDao.getFileKey(any(), any()))
          .thenAnswer((invocation) => Future.value(SecretKey([])));
      when(() => mockDriveDao.getDriveKey(any(), any()))
          .thenAnswer((invocation) => Future.value(SecretKey([])));
      when(() => mockArweaveService.getTransactionDetails(any())).thenAnswer(
          (invocation) => Future.value(MockTransactionCommonMixin()));
      when(() => mockDecrypt.decryptTransactionData(any(), any(), any()))
          .thenAnswer((invocation) => Future.value(Uint8List(100)));
    });
    blocTest<ProfileFileDownloadCubit, FileDownloadState>(
      'should download a private file',
      build: () => profileFileDownloadCubit = ProfileFileDownloadCubit(
        file: testFile,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
      ),
      act: (bloc) {
        profileFileDownloadCubit.download(SecretKey([]));
      },
      expect: () => <FileDownloadState>[
        FileDownloadInProgress(
          fileName: testFile.name,
          totalByteCount: testFile.size,
        ),
        FileDownloadSuccess(
          bytes: Uint8List(100),
          fileName: testFile.name,
          mimeType: testFile.contentType,
          lastModified: testFile.lastModifiedDate,
        ),
      ],
    );

    blocTest<ProfileFileDownloadCubit, FileDownloadState>(
      'should download a public file',
      build: () => profileFileDownloadCubit = ProfileFileDownloadCubit(
        file: testFile,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
      ),
      setUp: () {
        when(() => mockARFSRepository.getDriveById(any()))
            .thenAnswer((_) async => mockDrivePublic);
      },
      act: (bloc) {
        profileFileDownloadCubit.download(SecretKey([]));
      },
      verify: (bloc) {
        /// public files should not call these functions
        verifyNever(() => mockDriveDao.getFileKey(any(), any()));
        verifyNever(() => mockDriveDao.getDriveKey(any(), any()));
        verifyNever(
            () => mockDecrypt.decryptTransactionData(any(), any(), any()));
      },
      expect: () => <FileDownloadState>[
        FileDownloadInProgress(
          fileName: testFile.name,
          totalByteCount: testFile.size,
        ),
        FileDownloadSuccess(
          bytes: Uint8List(100),
          fileName: testFile.name,
          mimeType: testFile.contentType,
          lastModified: testFile.lastModifiedDate,
        ),
      ],
    );

    blocTest<ProfileFileDownloadCubit, FileDownloadState>(
      'should download with success a PRIVATE file above limit if the platform is not mobile',
      build: () => profileFileDownloadCubit = ProfileFileDownloadCubit(
        file: testFileAboveLimit,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
      ),
      setUp: () {
        AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

        /// Using a private drive
        when(() => mockARFSRepository.getDriveById(any()))
            .thenAnswer((_) async => mockDrivePrivate);
      },
      act: (bloc) async {
        await profileFileDownloadCubit.download(SecretKey([]));
      },
      expect: () => <FileDownloadState>[
        FileDownloadInProgress(
          fileName: testFileAboveLimit.name,
          totalByteCount: testFileAboveLimit.size,
        ),
        FileDownloadSuccess(
          bytes: Uint8List(100),
          fileName: testFileAboveLimit.name,
          mimeType: testFileAboveLimit.contentType,
          lastModified: testFileAboveLimit.lastModifiedDate,
        ),
      ],
    );

    blocTest<ProfileFileDownloadCubit, FileDownloadState>(
      'should emit a FileDownloadFailure with fileAboveLimit reason when mobile',
      build: () => profileFileDownloadCubit = ProfileFileDownloadCubit(
        file: testFileAboveLimit,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
      ),
      setUp: () {
        AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

        /// Using a private drive
        when(() => mockARFSRepository.getDriveById(any()))
            .thenAnswer((_) async => mockDrivePrivate);
      },
      act: (bloc) {
        profileFileDownloadCubit.download(SecretKey([]));
      },
      expect: () => <FileDownloadState>[
        const FileDownloadFailure(
          FileDownloadFailureReason.fileAboveLimit,
        ),
      ],
    );

    /// File is under private limits
    /// File is above the warning limit
    blocTest<ProfileFileDownloadCubit, FileDownloadState>(
      'should emit a FileDownloadWarning',
      build: () => profileFileDownloadCubit = ProfileFileDownloadCubit(
        file: testFileUnderPrivateLimitAndAboveWarningLimit,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
      ),
      setUp: () {
        AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

        /// Using a private drive
        when(() => mockARFSRepository.getDriveById(any()))
            .thenAnswer((_) async => mockDrivePrivate);
      },
      act: (bloc) {
        profileFileDownloadCubit.download(SecretKey([]));
      },
      expect: () => <FileDownloadState>[
        const FileDownloadWarning(),
      ],
    );

    blocTest<ProfileFileDownloadCubit, FileDownloadState>(
      'should download a PUBLIC file with size above PRIVATE limit',
      build: () => profileFileDownloadCubit = ProfileFileDownloadCubit(
        file: testFileAboveLimit,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
      ),
      setUp: () {
        AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

        /// Using a public drive
        when(() => mockARFSRepository.getDriveById(any()))
            .thenAnswer((_) async => mockDrivePublic);
      },
      act: (bloc) {
        profileFileDownloadCubit.download(SecretKey([]));
      },
      expect: () => <FileDownloadState>[
        FileDownloadInProgress(
          fileName: testFileAboveLimit.name,
          totalByteCount: testFileAboveLimit.size,
        ),
        FileDownloadSuccess(
          bytes: Uint8List(100),
          fileName: testFileAboveLimit.name,
          mimeType: testFileAboveLimit.contentType,
          lastModified: testFileAboveLimit.lastModifiedDate,
        ),
      ],
      verify: (bloc) {
        /// public files should not call these functions
        verifyNever(() => mockDriveDao.getFileKey(any(), any()));
        verifyNever(() => mockDriveDao.getDriveKey(any(), any()));
        verifyNever(
            () => mockDecrypt.decryptTransactionData(any(), any(), any()));
      },
    );

    blocTest<ProfileFileDownloadCubit, FileDownloadState>(
      'should emit a FileDownloadFailure with unknown reason when DownloadService throws',
      build: () => profileFileDownloadCubit = ProfileFileDownloadCubit(
        file: testFile,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
      ),
      setUp: () {
        AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

        /// Using a public drive
        when(() => mockARFSRepository.getDriveById(any()))
            .thenAnswer((_) async => mockDrivePublic);
        when(() => mockDownloadService.download(any()))
            .thenThrow((invocation) => Exception());
      },
      act: (bloc) {
        profileFileDownloadCubit.download(SecretKey([]));
      },
      expect: () => <FileDownloadState>[
        FileDownloadInProgress(
          fileName: testFile.name,
          totalByteCount: testFile.size,
        ),
        const FileDownloadFailure(FileDownloadFailureReason.unknownError),
      ],
      verify: (bloc) {
        /// public files should not call these functions
        verifyNever(() => mockDriveDao.getFileKey(any(), any()));
        verifyNever(() => mockDriveDao.getDriveKey(any(), any()));
        verifyNever(
            () => mockDecrypt.decryptTransactionData(any(), any(), any()));
      },
    );

    blocTest<ProfileFileDownloadCubit, FileDownloadState>(
      'should emit a FileDownloadFailure with unknown reason when Decrypt throws',
      build: () => profileFileDownloadCubit = ProfileFileDownloadCubit(
        file: testFile,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
      ),
      setUp: () {
        AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

        /// Using a private drive
        when(() => mockARFSRepository.getDriveById(any()))
            .thenAnswer((_) async => mockDrivePrivate);
        when(() => mockDecrypt.decryptTransactionData(any(), any(), any()))
            .thenThrow((invocation) => Exception());
      },
      act: (bloc) {
        profileFileDownloadCubit.download(SecretKey([]));
      },
      expect: () => <FileDownloadState>[
        FileDownloadInProgress(
          fileName: testFile.name,
          totalByteCount: testFile.size,
        ),
        const FileDownloadFailure(FileDownloadFailureReason.unknownError),
      ],
    );

    blocTest<ProfileFileDownloadCubit, FileDownloadState>(
      'should emit a FileDownloadFailure with unknown reason when Decrypt throws',
      build: () => profileFileDownloadCubit = ProfileFileDownloadCubit(
        file: testFile,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
      ),
      setUp: () {
        AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

        /// Using a private drive
        when(() => mockARFSRepository.getDriveById(any()))
            .thenAnswer((_) async => mockDrivePrivate);
        when(() => mockDecrypt.decryptTransactionData(any(), any(), any()))
            .thenThrow((invocation) => Exception());
      },
      act: (bloc) {
        profileFileDownloadCubit.download(SecretKey([]));
      },
      expect: () => <FileDownloadState>[
        FileDownloadInProgress(
          fileName: testFile.name,
          totalByteCount: testFile.size,
        ),
        const FileDownloadFailure(FileDownloadFailureReason.unknownError),
      ],
    );
  });

  group('Testing download method mocking platform to mobile', () {
    group('Testing download method mocking platform to mobile', () {
      blocTest<ProfileFileDownloadCubit, FileDownloadState>(
          'should emit a FileDownloadWithProgress and FileDownloadFinishedWithSuccess when iOS',
          build: () => profileFileDownloadCubit = ProfileFileDownloadCubit(
                file: testFile,
                driveDao: mockDriveDao,
                arweave: mockArweaveService,
                downloader: mockArDriveDownloader,
                decrypt: mockDecrypt,
                downloadService: mockDownloadService,
                arfsRepository: mockARFSRepository,
              ),
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.iOS);

            /// Using a private drive
            when(() => mockARFSRepository.getDriveById(any()))
                .thenAnswer((_) async => mockDrivePublic);
            when(() => mockArDriveDownloader.downloadFile(any(), any()))
                .thenAnswer((i) => mockDownloadProgress());
            when(() => mockArweaveService.client).thenReturn(
                Arweave(gatewayUrl: Uri.parse('http://example.com')));
          },
          act: (bloc) {
            profileFileDownloadCubit.download(SecretKey([]));
          },
          expect: () => <FileDownloadState>[
                FileDownloadWithProgress(
                  fileName: testFile.name,
                  fileSize: testFile.size,
                  progress: 100,
                ),
                FileDownloadFinishedWithSuccess(fileName: testFile.name),
              ],
          verify: (bloc) {
            /// public files on mobile should not call these functions
            verifyNever(() => mockDownloadService.download(any()));
            verifyNever(() => mockDriveDao.getFileKey(any(), any()));
            verifyNever(() => mockDriveDao.getDriveKey(any(), any()));
            verifyNever(
                () => mockDecrypt.decryptTransactionData(any(), any(), any()));
          });

      blocTest<ProfileFileDownloadCubit, FileDownloadState>(
          'should emit a FileDownloadWithProgress and FileDownloadFinishedWithSuccess when Android',
          build: () => profileFileDownloadCubit = ProfileFileDownloadCubit(
                file: testFile,
                driveDao: mockDriveDao,
                arweave: mockArweaveService,
                downloader: mockArDriveDownloader,
                decrypt: mockDecrypt,
                downloadService: mockDownloadService,
                arfsRepository: mockARFSRepository,
              ),
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

            /// Using a private drive
            when(() => mockARFSRepository.getDriveById(any()))
                .thenAnswer((_) async => mockDrivePublic);
            when(() => mockArDriveDownloader.downloadFile(any(), any()))
                .thenAnswer((i) => mockDownloadProgress());
            when(() => mockArweaveService.client).thenReturn(
                Arweave(gatewayUrl: Uri.parse('http://example.com')));
          },
          act: (bloc) {
            profileFileDownloadCubit.download(SecretKey([]));
          },
          expect: () => <FileDownloadState>[
                FileDownloadWithProgress(
                  fileName: testFile.name,
                  fileSize: testFile.size,
                  progress: 100,
                ),
                FileDownloadFinishedWithSuccess(fileName: testFile.name),
              ],
          verify: (bloc) {
            /// public files on mobile should not call these functions
            verifyNever(() => mockDownloadService.download(any()));
            verifyNever(() => mockDriveDao.getFileKey(any(), any()));
            verifyNever(() => mockDriveDao.getDriveKey(any(), any()));
            verifyNever(
                () => mockDecrypt.decryptTransactionData(any(), any(), any()));
          });

      blocTest<ProfileFileDownloadCubit, FileDownloadState>(
          'should download a public file using DownloadService instead ArDriveDownloader when platform differnt from mobile',
          build: () => profileFileDownloadCubit = ProfileFileDownloadCubit(
                file: testFile,
                driveDao: mockDriveDao,
                arweave: mockArweaveService,
                downloader: mockArDriveDownloader,
                decrypt: mockDecrypt,
                downloadService: mockDownloadService,
                arfsRepository: mockARFSRepository,
              ),
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

            /// Using a private drive
            when(() => mockARFSRepository.getDriveById(any()))
                .thenAnswer((_) async => mockDrivePublic);
          },
          verify: (bloc) {
            /// public files on mobile should not call these functions
            verifyNever(() => mockArDriveDownloader.downloadFile(any(), any()));
          });
    });

    blocTest<ProfileFileDownloadCubit, FileDownloadState>(
        'should emit a FileDownloadAborted',
        build: () => profileFileDownloadCubit = ProfileFileDownloadCubit(
              file: testFile,
              driveDao: mockDriveDao,
              arweave: mockArweaveService,
              downloader: mockArDriveDownloader,
              decrypt: mockDecrypt,
              downloadService: mockDownloadService,
              arfsRepository: mockARFSRepository,
            ),
        setUp: () {
          AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

          /// Using a private drive
          when(() => mockARFSRepository.getDriveById(any()))
              .thenAnswer((_) async => mockDrivePublic);

          /// This will emit a new progress for each seconds
          /// so we have time to abort the download and check how much it
          /// downloaded
          when(() => mockArDriveDownloader.downloadFile(any(), any()))
              .thenAnswer((i) => mockDownloadInProgress());
          when(() => mockArDriveDownloader.cancelDownload())
              .thenAnswer((i) async {});
          when(() => mockArweaveService.client)
              .thenReturn(Arweave(gatewayUrl: Uri.parse('http://example.com')));
        },
        act: (bloc) async {
          profileFileDownloadCubit.download(SecretKey([]));
          await Future.delayed(const Duration(seconds: 3));
          await profileFileDownloadCubit.abortDownload();
        },
        expect: () => <FileDownloadState>[
              FileDownloadWithProgress(
                fileName: testFile.name,
                fileSize: testFile.size,
                progress: 1,
              ),
              FileDownloadWithProgress(
                fileName: testFile.name,
                fileSize: testFile.size,
                progress: 2,
              ),
              FileDownloadAborted(),
            ],
        verify: (bloc) {
          verify(() => mockArDriveDownloader.cancelDownload());

          /// public files on mobile should not call these functions
          verifyNever(() => mockDownloadService.download(any()));
          verifyNever(() => mockDriveDao.getFileKey(any(), any()));
          verifyNever(() => mockDriveDao.getDriveKey(any(), any()));
          verifyNever(
              () => mockDecrypt.decryptTransactionData(any(), any(), any()));
        });
  });
}
