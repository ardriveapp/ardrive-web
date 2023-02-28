import 'dart:async';

import 'package:ardrive/blocs/file_download/file_download_cubit.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/core/decrypt.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/crypto/authenticate.dart';
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

class MockIOFile extends IOFile {
  final DateTime _lastModifiedDate;
  final String _name;
  final String _path;
  final Uint8List _data;

  MockIOFile({
    required super.contentType,
    required DateTime lastModifiedDate,
    required String name,
    required String path,
    required Uint8List data,
  }) : _lastModifiedDate = lastModifiedDate,
       _name = name,
       _path = path,
       _data = data;

  @override
  DateTime get lastModifiedDate => _lastModifiedDate;

  @override
  int get length => _data.length;
  
  @override
  String get name => _name;

  @override
  String get path => _path;

  @override
  Stream<Uint8List> openReadStream([int start = 0, int? end]) => Stream.value(_data);

  @override
  Future<Uint8List> readAsBytes() => Future.value(_data);

  @override
  Future<String> readAsString() async => Future.value(String.fromCharCodes(_data));
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
  late StreamPersonalFileDownloadCubit streamPersonalFileDownloadCubit;
  late DriveDao mockDriveDao;
  late ArweaveService mockArweaveService;
  late ArDriveDownloader mockArDriveDownloader;
  late Decrypt mockDecrypt;
  late DownloadService mockDownloadService;
  late ARFSRepository mockARFSRepository;
  late ArDriveIO mockArDriveIO;
  late IOFileAdapter mockIOFileAdapter;
  late Authenticate mockAuthenticate;

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

  MockIOFile mockIOFileExample = MockIOFile(
    contentType: 'test/content-type',
    lastModifiedDate: DateTime.now(),
    name: 'testName.test',
    path: '',
    data: Uint8List(100),
  );

  setUpAll(() {
    registerFallbackValue(SecretKey([]));
    registerFallbackValue(MockTransactionCommonMixin());
    registerFallbackValue(Uint8List(100));
    registerFallbackValue(Stream.value(Uint8List(100)));
    registerFallbackValue(Future.value(Stream.value(Uint8List(100))));
    registerFallbackValue(mockDrivePrivate);
    registerFallbackValue(mockDrivePublic);
    registerFallbackValue(testFile);
    registerFallbackValue(mockDownloadProgress());
    registerFallbackValue(mockDownloadInProgress());
    registerFallbackValue(mockIOFileExample);
    registerFallbackValue(Future.value(true));
    registerFallbackValue(Completer<bool>());
  });

  setUp(() {
    mockDriveDao = MockDriveDao();
    mockArweaveService = MockArweaveService();
    mockArDriveDownloader = MockArDriveDownloader();
    mockDecrypt = MockDecrypt();
    mockDownloadService = MockDownloadService();
    mockARFSRepository = MockARFSRepository();
    mockArDriveIO = MockArDriveIO();
    mockIOFileAdapter = MockIOFileAdapter();
    mockAuthenticate = MockAuthenticate();
  });

  group('Testing download method', () {
    setUp(() {
      when(() => mockARFSRepository.getDriveById(any()))
          .thenAnswer((_) async => mockDrivePrivate);
      when(() => mockDownloadService.downloadStream(any(), any()))
          .thenAnswer((invocation) => Stream.value(Uint8List(100)));
      when(() => mockDriveDao.getFileKey(any(), any()))
          .thenAnswer((invocation) => Future.value(SecretKey([])));
      when(() => mockDriveDao.getDriveKey(any(), any()))
          .thenAnswer((invocation) => Future.value(SecretKey([])));
      when(() => mockArweaveService.getTransactionDetails(any()))
          .thenAnswer((invocation) => Future.value(MockTransactionCommonMixin()));
      when(() => mockArweaveService.getTransaction<TransactionStream>(any()))
          .thenAnswer((invocation) => Future.value(TransactionStream()));
      when(() => mockDecrypt.decryptTransactionDataStream(any(), any(), any()))
          .thenAnswer((invocation) => Future.value(Stream.value(Uint8List(100))));
      when(() => mockArDriveIO.saveFileStream(any(), any()))
          .thenAnswer((invocation) => Stream.value(SaveStatus(bytesSaved: 0, totalBytes: 0, saveResult: true)));
      when(() => mockIOFileExample.openReadStream(any(), any()))
          .thenAnswer((invocation) => Stream.fromIterable([Uint8List(100)]));
      when(() => mockIOFileAdapter.fromReadStreamGenerator(any(), any(), name: any(), lastModifiedDate: any(), contentType: any()))
          .thenAnswer((invocation) => Future.value(mockIOFileExample));
    });
    blocTest<StreamPersonalFileDownloadCubit, FileDownloadState>(
      'should download a private file',
      build: () => streamPersonalFileDownloadCubit = StreamPersonalFileDownloadCubit(
        file: testFile,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
        ardriveIo: mockArDriveIO,
        ioFileAdapter: mockIOFileAdapter,
        authenticate: mockAuthenticate,
      ),
      act: (bloc) {
        streamPersonalFileDownloadCubit.download(SecretKey([]));
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

    blocTest<StreamPersonalFileDownloadCubit, FileDownloadState>(
      'should download a public file',
      build: () => streamPersonalFileDownloadCubit = StreamPersonalFileDownloadCubit(
        file: testFile,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
        ardriveIo: mockArDriveIO,
        ioFileAdapter: mockIOFileAdapter,
        authenticate: mockAuthenticate,
      ),
      setUp: () {
        when(() => mockARFSRepository.getDriveById(any()))
            .thenAnswer((_) async => mockDrivePublic);
      },
      act: (bloc) {
        streamPersonalFileDownloadCubit.download(SecretKey([]));
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

    blocTest<StreamPersonalFileDownloadCubit, FileDownloadState>(
      'should download with success a PRIVATE file above limit if the platform is not mobile',
      build: () => streamPersonalFileDownloadCubit = StreamPersonalFileDownloadCubit(
        file: testFileAboveLimit,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
        ardriveIo: mockArDriveIO,
        ioFileAdapter: mockIOFileAdapter,
        authenticate: mockAuthenticate,
      ),
      setUp: () {
        AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

        /// Using a private drive
        when(() => mockARFSRepository.getDriveById(any()))
            .thenAnswer((_) async => mockDrivePrivate);
      },
      act: (bloc) async {
        await streamPersonalFileDownloadCubit.download(SecretKey([]));
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

    blocTest<StreamPersonalFileDownloadCubit, FileDownloadState>(
      'should emit a FileDownloadFailure with fileAboveLimit reason when mobile',
      build: () => streamPersonalFileDownloadCubit = StreamPersonalFileDownloadCubit(
        file: testFileAboveLimit,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
        ardriveIo: mockArDriveIO,
        ioFileAdapter: mockIOFileAdapter,
        authenticate: mockAuthenticate,
      ),
      setUp: () {
        AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

        /// Using a private drive
        when(() => mockARFSRepository.getDriveById(any()))
            .thenAnswer((_) async => mockDrivePrivate);
      },
      act: (bloc) {
        streamPersonalFileDownloadCubit.download(SecretKey([]));
      },
      expect: () => <FileDownloadState>[
        const FileDownloadFailure(
          FileDownloadFailureReason.fileAboveLimit,
        ),
      ],
    );

    /// File is under private limits
    /// File is above the warning limit
    blocTest<StreamPersonalFileDownloadCubit, FileDownloadState>(
      'should emit a FileDownloadWarning',
      build: () => streamPersonalFileDownloadCubit = StreamPersonalFileDownloadCubit(
        file: testFileUnderPrivateLimitAndAboveWarningLimit,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
        ardriveIo: mockArDriveIO,
        ioFileAdapter: mockIOFileAdapter,
        authenticate: mockAuthenticate,
      ),
      setUp: () {
        AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

        /// Using a private drive
        when(() => mockARFSRepository.getDriveById(any()))
            .thenAnswer((_) async => mockDrivePrivate);
      },
      act: (bloc) {
        streamPersonalFileDownloadCubit.download(SecretKey([]));
      },
      expect: () => <FileDownloadState>[
        const FileDownloadWarning(),
      ],
    );

    blocTest<StreamPersonalFileDownloadCubit, FileDownloadState>(
      'should download a PUBLIC file with size above PRIVATE limit',
      build: () => streamPersonalFileDownloadCubit = StreamPersonalFileDownloadCubit(
        file: testFileAboveLimit,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
        ardriveIo: mockArDriveIO,
        ioFileAdapter: mockIOFileAdapter,
        authenticate: mockAuthenticate,
      ),
      setUp: () {
        AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

        /// Using a public drive
        when(() => mockARFSRepository.getDriveById(any()))
            .thenAnswer((_) async => mockDrivePublic);
      },
      act: (bloc) {
        streamPersonalFileDownloadCubit.download(SecretKey([]));
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

    blocTest<StreamPersonalFileDownloadCubit, FileDownloadState>(
      'should emit a FileDownloadFailure with unknown reason when DownloadService throws',
      build: () => streamPersonalFileDownloadCubit = StreamPersonalFileDownloadCubit(
        file: testFile,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
        ardriveIo: mockArDriveIO,
        ioFileAdapter: mockIOFileAdapter,
        authenticate: mockAuthenticate,
      ),
      setUp: () {
        AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

        /// Using a public drive
        when(() => mockARFSRepository.getDriveById(any()))
            .thenAnswer((_) async => mockDrivePublic);
        when(() => mockDownloadService.downloadBuffer(any()))
            .thenThrow((invocation) => Exception());
      },
      act: (bloc) {
        streamPersonalFileDownloadCubit.download(SecretKey([]));
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

    blocTest<StreamPersonalFileDownloadCubit, FileDownloadState>(
      'should emit a FileDownloadFailure with unknown reason when Decrypt throws',
      build: () => streamPersonalFileDownloadCubit = StreamPersonalFileDownloadCubit(
        file: testFile,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
        ardriveIo: mockArDriveIO,
        ioFileAdapter: mockIOFileAdapter,
        authenticate: mockAuthenticate,
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
        streamPersonalFileDownloadCubit.download(SecretKey([]));
      },
      expect: () => <FileDownloadState>[
        FileDownloadInProgress(
          fileName: testFile.name,
          totalByteCount: testFile.size,
        ),
        const FileDownloadFailure(FileDownloadFailureReason.unknownError),
      ],
    );

    blocTest<StreamPersonalFileDownloadCubit, FileDownloadState>(
      'should emit a FileDownloadFailure with unknown reason when Decrypt throws',
      build: () => streamPersonalFileDownloadCubit = StreamPersonalFileDownloadCubit(
        file: testFile,
        driveDao: mockDriveDao,
        arweave: mockArweaveService,
        downloader: mockArDriveDownloader,
        decrypt: mockDecrypt,
        downloadService: mockDownloadService,
        arfsRepository: mockARFSRepository,
        ardriveIo: mockArDriveIO,
        ioFileAdapter: mockIOFileAdapter,
        authenticate: mockAuthenticate,
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
        streamPersonalFileDownloadCubit.download(SecretKey([]));
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
      blocTest<StreamPersonalFileDownloadCubit, FileDownloadState>(
          'should emit a FileDownloadWithProgress and FileDownloadFinishedWithSuccess when iOS',
          build: () => streamPersonalFileDownloadCubit = StreamPersonalFileDownloadCubit(
                file: testFile,
                driveDao: mockDriveDao,
                arweave: mockArweaveService,
                downloader: mockArDriveDownloader,
                decrypt: mockDecrypt,
                downloadService: mockDownloadService,
                arfsRepository: mockARFSRepository,
                ardriveIo: mockArDriveIO,
                ioFileAdapter: mockIOFileAdapter,
                authenticate: mockAuthenticate,
              ),
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.iOS);

            /// Using a private drive
            when(() => mockARFSRepository.getDriveById(any()))
                .thenAnswer((_) async => mockDrivePublic);
            when(() => mockArDriveDownloader.downloadFile(any(), any(), any()))
                .thenAnswer((i) => mockDownloadProgress());
            when(() => mockArweaveService.client).thenReturn(
                Arweave(gatewayUrl: Uri.parse('http://example.com')));
          },
          act: (bloc) {
            streamPersonalFileDownloadCubit.download(SecretKey([]));
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
            verifyNever(() => mockDownloadService.downloadBuffer(any()));
            verifyNever(() => mockDriveDao.getFileKey(any(), any()));
            verifyNever(() => mockDriveDao.getDriveKey(any(), any()));
            verifyNever(
                () => mockDecrypt.decryptTransactionData(any(), any(), any()));
          });

      blocTest<StreamPersonalFileDownloadCubit, FileDownloadState>(
          'should emit a FileDownloadWithProgress and FileDownloadFinishedWithSuccess when Android',
          build: () => streamPersonalFileDownloadCubit = StreamPersonalFileDownloadCubit(
                file: testFile,
                driveDao: mockDriveDao,
                arweave: mockArweaveService,
                downloader: mockArDriveDownloader,
                decrypt: mockDecrypt,
                downloadService: mockDownloadService,
                arfsRepository: mockARFSRepository,
                ardriveIo: mockArDriveIO,
                ioFileAdapter: mockIOFileAdapter,
                authenticate: mockAuthenticate,
              ),
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

            /// Using a private drive
            when(() => mockARFSRepository.getDriveById(any()))
                .thenAnswer((_) async => mockDrivePublic);
            when(() => mockArDriveDownloader.downloadFile(any(), any(), any()))
                .thenAnswer((i) => mockDownloadProgress());
            when(() => mockArweaveService.client).thenReturn(
                Arweave(gatewayUrl: Uri.parse('http://example.com')));
          },
          act: (bloc) {
            streamPersonalFileDownloadCubit.download(SecretKey([]));
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
            verifyNever(() => mockDownloadService.downloadBuffer(any()));
            verifyNever(() => mockDriveDao.getFileKey(any(), any()));
            verifyNever(() => mockDriveDao.getDriveKey(any(), any()));
            verifyNever(
                () => mockDecrypt.decryptTransactionData(any(), any(), any()));
          });

      blocTest<StreamPersonalFileDownloadCubit, FileDownloadState>(
          'should download a public file using DownloadService instead ArDriveDownloader when platform differnt from mobile',
          build: () => streamPersonalFileDownloadCubit = StreamPersonalFileDownloadCubit(
                file: testFile,
                driveDao: mockDriveDao,
                arweave: mockArweaveService,
                downloader: mockArDriveDownloader,
                decrypt: mockDecrypt,
                downloadService: mockDownloadService,
                arfsRepository: mockARFSRepository,
                ardriveIo: mockArDriveIO,
                ioFileAdapter: mockIOFileAdapter,
                authenticate: mockAuthenticate,
              ),
          setUp: () {
            AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

            /// Using a private drive
            when(() => mockARFSRepository.getDriveById(any()))
                .thenAnswer((_) async => mockDrivePublic);
          },
          verify: (bloc) {
            /// public files on mobile should not call these functions
            verifyNever(() => mockArDriveDownloader.downloadFile(any(), any(), any()));
          });
    });

    blocTest<StreamPersonalFileDownloadCubit, FileDownloadState>(
        'should emit a FileDownloadAborted',
        build: () => streamPersonalFileDownloadCubit = StreamPersonalFileDownloadCubit(
              file: testFile,
              driveDao: mockDriveDao,
              arweave: mockArweaveService,
              downloader: mockArDriveDownloader,
              decrypt: mockDecrypt,
              downloadService: mockDownloadService,
              arfsRepository: mockARFSRepository,
              ardriveIo: mockArDriveIO,
              ioFileAdapter: mockIOFileAdapter,
                authenticate: mockAuthenticate,
            ),
        setUp: () {
          AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

          /// Using a private drive
          when(() => mockARFSRepository.getDriveById(any()))
              .thenAnswer((_) async => mockDrivePublic);

          /// This will emit a new progress for each seconds
          /// so we have time to abort the download and check how much it
          /// downloaded
          when(() => mockArDriveDownloader.downloadFile(any(), any(), any()))
              .thenAnswer((i) => mockDownloadInProgress());
          when(() => mockArDriveDownloader.cancelDownload())
              .thenAnswer((i) async {});
          when(() => mockArweaveService.client)
              .thenReturn(Arweave(gatewayUrl: Uri.parse('http://example.com')));
        },
        act: (bloc) async {
          streamPersonalFileDownloadCubit.download(SecretKey([]));
          await Future.delayed(const Duration(seconds: 3));
          await streamPersonalFileDownloadCubit.abortDownload();
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
          verifyNever(() => mockArDriveDownloader.cancelDownload());

          /// public files on mobile should not call these functions
          verifyNever(() => mockDownloadService.downloadBuffer(any()));
          verifyNever(() => mockDriveDao.getFileKey(any(), any()));
          verifyNever(() => mockDriveDao.getDriveKey(any(), any()));
          verifyNever(
              () => mockDecrypt.decryptTransactionData(any(), any(), any()));
        });
  });
}
