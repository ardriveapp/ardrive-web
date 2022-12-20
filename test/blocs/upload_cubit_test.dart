import 'dart:io';
import 'dart:typed_data';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/models/upload_plan.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/types/winston.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

// TODO(thiagocarvalhodev): Test the case of remove files before download when pass ConflictingFileActions.SKIP.
// TODO: Test startUpload
void main() {
  // Mocks
  late DriveDao mockDriveDao;
  late MockArweaveService mockArweave;
  late MockPstService mockPst;
  late MockUploadPlanUtils mockUploadPlanUtils;
  MockProfileCubit? mockProfileCubit;

  const tDriveId = 'drive_id';
  const tRootFolderId = 'root-folder-id';
  const tRootFolderFileCount = 5;
  final tDefaultDate = DateTime.parse('2022-09-06');

  const tNestedFolderId = 'nested-folder-id';
  const tNestedFolderFileCount = 5;

  const tEmptyNestedFolderIdPrefix = 'empty-nested-folder-id';
  const tEmptyNestedFolderCount = 5;

  late Database db;
  late List<UploadFile> tAllConflictingFiles;
  late List<UploadFile> tSomeConflictingFiles;
  late List<UploadFile> tNoConflictingFiles;

  final tWallet = getTestWallet();
  String? tWalletAddress;

  final tKeyBytes = Uint8List(32);
  fillBytesWithSecureRandom(tKeyBytes);

  setUpAll(() async {
    registerFallbackValue(SecretKey([]));
    registerFallbackValue(Wallet());
    registerFallbackValue(FolderEntry(
        id: '',
        dateCreated: tDefaultDate,
        driveId: '',
        isGhost: false,
        lastUpdated: tDefaultDate,
        name: '',
        parentFolderId: '',
        path: ''));

    registerFallbackValue(Drive(
        id: '',
        rootFolderId: '',
        name: '',
        ownerAddress: '',
        dateCreated: tDefaultDate,
        lastUpdated: tDefaultDate,
        privacy: ''));

    tWalletAddress = await tWallet.getAddress();

    db = getTestDb();

    // We need a real file path because in the UploadCubit we needs the size of the file
    // to know if the file is `tooLargeFiles`.
    final tRealPathFile = await IOFile.fromData(
        File('assets/config/dev.json').readAsBytesSync(),
        lastModifiedDate: tDefaultDate,
        name: 'file');

    // The `addTestFilesToDb` will generate files with this path and name, so it
    // will be a confliting file.
    final tConflictingFile = await IOFile.fromData(Uint8List.fromList([1]),
        lastModifiedDate: tDefaultDate, name: '${tRootFolderId}1');

    // Contains only conflicting files.
    tAllConflictingFiles = <UploadFile>[
      UploadFile(ioFile: tConflictingFile, parentFolderId: tRootFolderId)
    ];

    final tDumbTestFile = await IOFile.fromData(Uint8List.fromList([1]),
        name: 'dumb_test_path', lastModifiedDate: tDefaultDate);

    /// This list contains conflicting and non conflicting files.
    tSomeConflictingFiles = <UploadFile>[
      UploadFile(ioFile: tConflictingFile, parentFolderId: tRootFolderId),
      UploadFile(ioFile: tDumbTestFile, parentFolderId: tRootFolderId)
    ];

    tNoConflictingFiles = <UploadFile>[
      UploadFile(ioFile: tRealPathFile, parentFolderId: tRootFolderId)
    ];

    mockArweave = MockArweaveService();
    mockPst = MockPstService();
    mockDriveDao = db.driveDao;
    mockProfileCubit = MockProfileCubit();
    mockUploadPlanUtils = MockUploadPlanUtils();

    // Setup mock drive.
    await addTestFilesToDb(
      db,
      driveId: tDriveId,
      emptyNestedFolderCount: tEmptyNestedFolderCount,
      emptyNestedFolderIdPrefix: tEmptyNestedFolderIdPrefix,
      rootFolderId: tRootFolderId,
      rootFolderFileCount: tRootFolderFileCount,
      nestedFolderId: tNestedFolderId,
      nestedFolderFileCount: tNestedFolderFileCount,
    );
  });

  UploadCubit getUploadCubitInstanceWith(List<UploadFile> files) {
    return UploadCubit(
        uploadPlanUtils: mockUploadPlanUtils,
        driveId: tDriveId,
        parentFolderId: tRootFolderId,
        files: files,
        profileCubit: mockProfileCubit!,
        driveDao: mockDriveDao,
        arweave: mockArweave,
        turboService: TurboService(
          turboUri: Uri.parse('mockTurboURl.dev'),
          allowedDataItemSize: 0,
          httpClient: ArDriveHTTP(),
        ),
        pst: mockPst);
  }

  void setDumbUploadPlan() => when(() => mockUploadPlanUtils.filesToUploadPlan(
          files: any(named: 'files'),
          cipherKey: any(named: 'cipherKey'),
          wallet: any(named: 'wallet'),
          conflictingFiles: any(named: 'conflictingFiles'),
          targetDrive: any(named: 'targetDrive'),
          targetFolder: any<FolderEntry>(named: 'targetFolder')))
      .thenAnswer((invocation) => Future.value(
            UploadPlan.create(
              fileV2UploadHandles: {},
              fileDataItemUploadHandles: {},
              folderDataItemUploadHandles: {},
            ),
          ));

  group('check if there are some conflicting file', () {
    setUp(() {
      when(() => mockProfileCubit!.state).thenReturn(
        ProfileLoggedIn(
          username: 'Test',
          password: '123',
          wallet: tWallet,
          walletAddress: tWalletAddress!,
          walletBalance: BigInt.one,
          cipherKey: SecretKey(tKeyBytes),
        ),
      );
      when(() => mockProfileCubit!.checkIfWalletMismatch())
          .thenAnswer((i) => Future.value(false));
      when(() => mockProfileCubit!.isCurrentProfileArConnect())
          .thenAnswer((i) => Future.value(false));
      when(() => mockPst.getPSTFee(BigInt.zero))
          .thenAnswer((invocation) => Future.value(Winston(BigInt.zero)));
      when(() => mockArweave.getArUsdConversionRate())
          .thenAnswer((invocation) => Future.value(10));
      setDumbUploadPlan();
    });
    blocTest<UploadCubit, UploadState>(
        'should found the conflicting files correctly and set isAllFilesConflicting to true'
        ' when all files are conflicting',
        build: () {
          return getUploadCubitInstanceWith(tAllConflictingFiles);
        },
        act: (cubit) async {
          await cubit.startUploadPreparation();
          await cubit.checkConflictingFiles();
        },
        expect: () => <dynamic>[
              const TypeMatcher<UploadPreparationInitialized>(),
              const TypeMatcher<UploadPreparationInProgress>(),
              UploadFileConflict(
                  areAllFilesConflicting: true,
                  conflictingFileNames: const ['${tRootFolderId}1']),
            ]);

    blocTest<UploadCubit, UploadState>(
        'should found the conflicting files correctly and set isAllFilesConflicting to false'
        ' when there is at least one file that is not conflicting',
        build: () {
          return getUploadCubitInstanceWith(tSomeConflictingFiles);
        },
        tearDown: () {},
        act: (cubit) async {
          await cubit.startUploadPreparation();
          await cubit.checkConflictingFiles();
        },
        expect: () => <dynamic>[
              const TypeMatcher<UploadPreparationInitialized>(),
              const TypeMatcher<UploadPreparationInProgress>(),
              UploadFileConflict(
                  areAllFilesConflicting: false,
                  conflictingFileNames: const ['${tRootFolderId}1'])
            ]);

    blocTest<UploadCubit, UploadState>(
        'should not found any conflicting file when there isnt any conflicting file to upload',
        build: () {
          return getUploadCubitInstanceWith(tNoConflictingFiles);
        },
        act: (cubit) async {
          await cubit.startUploadPreparation();
          await cubit.checkConflictingFiles();
        },
        expect: () => <dynamic>[
              const TypeMatcher<UploadPreparationInitialized>(),
              const TypeMatcher<UploadPreparationInProgress>(),
              const TypeMatcher<UploadReady>()
            ]);
  });

  group('prepare upload plan and costs estimates', () {
    setUp(() {
      when(() => mockProfileCubit!.state).thenReturn(
        ProfileLoggedIn(
          username: 'Test',
          password: '123',
          wallet: tWallet,
          walletAddress: tWalletAddress!,
          walletBalance: BigInt.one,
          cipherKey: SecretKey(tKeyBytes),
        ),
      );
      when(() => mockProfileCubit!.checkIfWalletMismatch())
          .thenAnswer((i) => Future.value(false));
      when(() => mockPst.getPSTFee(BigInt.zero))
          .thenAnswer((invocation) => Future.value(Winston(BigInt.zero)));
      when(() => mockArweave.getArUsdConversionRate())
          .thenAnswer((invocation) => Future.value(10));
      when(() => mockUploadPlanUtils.filesToUploadPlan(
          files: any(named: 'files'),
          cipherKey: any(named: 'cipherKey'),
          wallet: any(named: 'wallet'),
          conflictingFiles: any(named: 'conflictingFiles'),
          targetDrive: any(named: 'targetDrive'),
          targetFolder: any<FolderEntry>(named: 'targetFolder'))).thenAnswer(
        (invocation) => Future.value(
          UploadPlan.create(
            fileV2UploadHandles: {},
            fileDataItemUploadHandles: {},
            folderDataItemUploadHandles: {},
          ),
        ),
      );
      when(() => mockProfileCubit!.isCurrentProfileArConnect())
          .thenAnswer((i) => Future.value(true));
    });

    blocTest<UploadCubit, UploadState>(
      'should set the isArconnect to true when user is ArConnect '
      'and prepare the upload and set it to ready',
      build: () {
        return getUploadCubitInstanceWith(tNoConflictingFiles);
      },
      act: (cubit) async {
        await cubit.startUploadPreparation();
        await cubit.prepareUploadPlanAndCostEstimates();
      },
      expect: () => <dynamic>[
        UploadPreparationInitialized(),
        UploadPreparationInProgress(isArConnect: true),
        const TypeMatcher<UploadReady>()
      ],
    );
    blocTest<UploadCubit, UploadState>(
      'should set the isArconnect to false when user isnt ArConnect '
      'and prepare the upload and set it to ready',
      setUp: () {
        when(() => mockProfileCubit!.isCurrentProfileArConnect())
            .thenAnswer((i) => Future.value(false));
      },
      build: () {
        return getUploadCubitInstanceWith(tNoConflictingFiles);
      },
      act: (cubit) async {
        await cubit.startUploadPreparation();
        await cubit.prepareUploadPlanAndCostEstimates();
      },
      expect: () => <dynamic>[
        UploadPreparationInitialized(),
        UploadPreparationInProgress(isArConnect: false),
        const TypeMatcher<UploadReady>()
      ],
    );

    group(
      'file size above limit',
      () {
        late UploadFile tTooLargeFile;
        late List<UploadFile> tTooLargeFiles;

        blocTest<UploadCubit, UploadState>(
          'should emit UploadFileTooLarge with hasFilesToUpload false when we have'
          ' only a file larger than publicFileSizeLimit'
          ' is intended to upload',
          setUp: () async {
            final tFile = File('some_file.txt');
            tFile.writeAsBytesSync(Uint8List(publicFileSizeLimit.toInt() + 1));
            tTooLargeFile = UploadFile(
                ioFile: await IOFile.fromData(tFile.readAsBytesSync(),
                    lastModifiedDate: tDefaultDate, name: 'some_file.txt'),
                parentFolderId: tRootFolderId);
            tTooLargeFiles = [tTooLargeFile];
          },
          build: () {
            return getUploadCubitInstanceWith(tTooLargeFiles);
          },
          tearDown: () {
            File('some_file.txt').deleteSync();
          },
          act: (cubit) async {
            await cubit.startUploadPreparation();
            await cubit.checkFilesAboveLimit();
          },
          expect: () => <dynamic>[
            UploadPreparationInitialized(),
            UploadFileTooLarge(
                hasFilesToUpload: false,
                tooLargeFileNames: [tTooLargeFiles.first.getIdentifier()],
                isPrivate: false)
          ],
        );

        blocTest<UploadCubit, UploadState>(
          'should emit UploadFileTooLarge with hasFilesToUpload true when we have'
          ' others files not too large to upload',
          setUp: () async {
            final tFile = File('some_file.txt');
            tFile.writeAsBytesSync(Uint8List(publicFileSizeLimit.toInt() + 1));
            tTooLargeFile = UploadFile(
                ioFile: await IOFile.fromData(
                    File(tFile.path).readAsBytesSync(),
                    lastModifiedDate: tDefaultDate,
                    name: 'some_file.txt'),
                parentFolderId: tRootFolderId);
          },
          build: () {
            final tTooLargeFilesWithNoConflictingFiles = tNoConflictingFiles
              ..add(tTooLargeFile);

            return getUploadCubitInstanceWith(
                tTooLargeFilesWithNoConflictingFiles);
          },
          tearDown: () {
            File('some_file.txt').deleteSync();
          },
          act: (cubit) async {
            await cubit.startUploadPreparation();
            await cubit.checkFilesAboveLimit();
          },
          expect: () => <dynamic>[
            UploadPreparationInitialized(),
            UploadFileTooLarge(
                hasFilesToUpload: false,
                tooLargeFileNames: [tTooLargeFiles.first.getIdentifier()],
                isPrivate: false)
          ],
        );

        blocTest<UploadCubit, UploadState>(
          'should emit UploadReady when we have too large files but at least a not too large'
          ' and skip large files',
          setUp: () async {
            final tFile = File('some_file.txt');

            tFile.writeAsBytesSync(Uint8List(publicFileSizeLimit.toInt() + 1));
            tTooLargeFile = UploadFile(
                ioFile: await IOFile.fromData(
                    File(tFile.path).readAsBytesSync(),
                    lastModifiedDate: tDefaultDate,
                    name: 'some_file.txt'),
                parentFolderId: tRootFolderId);
            when(() => mockProfileCubit!.isCurrentProfileArConnect())
                .thenAnswer((i) => Future.value(false));
          },
          build: () {
            final tTooLargeFilesWithNoConflictingFiles = tNoConflictingFiles
              ..add(tTooLargeFile);
            final files =
                tNoConflictingFiles + tTooLargeFilesWithNoConflictingFiles;
            return getUploadCubitInstanceWith(files);
          },
          act: (cubit) async {
            await cubit.startUploadPreparation();
            await cubit.checkFilesAboveLimit();
            await cubit.skipLargeFilesAndCheckForConflicts();
          },
          tearDown: () {
            File('some_file.txt').deleteSync();
          },
          expect: () => <dynamic>[
            UploadPreparationInitialized(),
            const TypeMatcher<UploadFileTooLarge>(),
            const TypeMatcher<UploadPreparationInProgress>(),
            const TypeMatcher<UploadReady>(),
          ],
        );
      },
    );

    blocTest<UploadCubit, UploadState>(
      'should emit the upload wallet mismatch state and does nothing',
      setUp: () {
        // wallet mismatch
        when(() => mockProfileCubit!.checkIfWalletMismatch())
            .thenAnswer((i) => Future.value(true));
      },
      build: () {
        return getUploadCubitInstanceWith(tNoConflictingFiles);
      },
      act: (cubit) async {
        await cubit.startUploadPreparation();
        await cubit.prepareUploadPlanAndCostEstimates();
      },
      expect: () =>
          <UploadState>[UploadPreparationInitialized(), UploadWalletMismatch()],
    );
  });
}
