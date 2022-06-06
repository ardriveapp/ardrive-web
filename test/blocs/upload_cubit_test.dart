import 'dart:io';
import 'dart:typed_data';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/enums/conflicting_files_actions.dart';
import 'package:ardrive/blocs/upload/models/io_file.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/models/upload_plan.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
import 'package:file_selector/file_selector.dart';
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
        dateCreated: DateTime.now(),
        driveId: '',
        isGhost: false,
        lastUpdated: DateTime.now(),
        name: '',
        parentFolderId: '',
        path: ''));

    registerFallbackValue(Drive(
        id: '',
        rootFolderId: '',
        name: '',
        ownerAddress: '',
        dateCreated: DateTime.now(),
        lastUpdated: DateTime.now(),
        privacy: ''));

    tWalletAddress = await tWallet.getAddress();

    db = getTestDb();

    // We need a real file path because in the UploadCubit we needs the size of the file
    // to know if the file is `tooLargeFiles`.
    final _tRealPathFile =
        await IOFile.fromXFile(XFile('assets/config/dev.json'), tRootFolderId);

    // The `addTestFilesToDb` will generate files with this path and name, so it
    // will be a confliting file.
    final tConflictingFile =
        await IOFile.fromXFile(XFile(tRootFolderId + '1'), tRootFolderId);

    // Contains only conflicting files.
    tAllConflictingFiles = <UploadFile>[tConflictingFile];

    /// This list contains conflicting and non conflicting files.
    tSomeConflictingFiles = <UploadFile>[
      tConflictingFile,
      await IOFile.fromXFile(XFile('dumb_test_path'), tRootFolderId)
    ];

    tNoConflictingFiles = <UploadFile>[_tRealPathFile];

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
        folderId: tRootFolderId,
        files: files,
        profileCubit: mockProfileCubit!,
        driveDao: mockDriveDao,
        arweave: mockArweave,
        pst: mockPst);
  }

  void setDumbUploadPlan() => when(() => mockUploadPlanUtils.filesToUploadPlan(
          files: any(named: 'files'),
          cipherKey: any(named: 'cipherKey'),
          wallet: any(named: 'wallet'),
          conflictingFiles: any(named: 'conflictingFiles'),
          targetDrive: any(named: 'targetDrive'),
          targetFolder: any<FolderEntry>(named: 'folderEntry')))
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
          .thenAnswer((invocation) => Future.value(BigInt.zero));
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
              TypeMatcher<UploadPreparationInitialized>(),
              TypeMatcher<UploadPreparationInProgress>(),
              UploadFileConflict(
                  areAllFilesConflicting: true,
                  conflictingFileNames: [tRootFolderId + '1']),
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
              TypeMatcher<UploadPreparationInitialized>(),
              TypeMatcher<UploadPreparationInProgress>(),
              UploadFileConflict(
                  areAllFilesConflicting: false,
                  conflictingFileNames: [tRootFolderId + '1'])
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
              TypeMatcher<UploadPreparationInitialized>(),
              TypeMatcher<UploadPreparationInProgress>(),
              TypeMatcher<UploadReady>()
            ]);
  });

  group('prepare upload plan and costs estimates', () {
    late UploadFile tTooLargeFile;
    late List<UploadFile> tTooLargeFiles;

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
          .thenAnswer((invocation) => Future.value(BigInt.zero));
      when(() => mockArweave.getArUsdConversionRate())
          .thenAnswer((invocation) => Future.value(10));
      when(() => mockUploadPlanUtils.filesToUploadPlan(
          files: any(named: 'files'),
          cipherKey: any(named: 'cipherKey'),
          wallet: any(named: 'wallet'),
          conflictingFiles: any(named: 'conflictingFiles'),
          targetDrive: any(named: 'targetDrive'),
          targetFolder: any<FolderEntry>(named: 'folderEntry'))).thenAnswer(
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
        TypeMatcher<UploadReady>()
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
        TypeMatcher<UploadReady>()
      ],
    );

    blocTest<UploadCubit, UploadState>(
      'should emit UploadFileTooLarge with hasFilesToUpload false when we have'
      ' only a file larger than publicFileSizeLimit'
      ' is intended to upload',
      setUp: () async {
        final tFile = File('some_file.txt');
        tFile.writeAsBytesSync(Uint8List(publicFileSizeLimit.toInt() + 1));
        tTooLargeFile = await IOFile.fromXFile(
          XFile(tFile.path),
          tRootFolderId,
        );
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
        await cubit.prepareUploadPlanAndCostEstimates();
      },
      expect: () => <dynamic>[
        UploadPreparationInitialized(),
        TypeMatcher<UploadPreparationInProgress>(),
        UploadFileTooLarge(
            hasFilesToUpload: false,
            tooLargeFileNames: [tTooLargeFiles.first.name],
            isPrivate: false)
      ],
    );

    blocTest<UploadCubit, UploadState>(
      'should emit UploadFileTooLarge with hasFilesToUpload true when we have'
      ' others files not too large to upload',
      setUp: () async {
        final tFile = File('some_file.txt');
        tFile.writeAsBytesSync(Uint8List(publicFileSizeLimit.toInt() + 1));
        tTooLargeFile = await IOFile.fromXFile(
          XFile(tFile.path),
          tRootFolderId,
        );
      },
      build: () {
        final tTooLargeFilesWithNoConflictingFiles = tNoConflictingFiles
          ..add(tTooLargeFile);

        return getUploadCubitInstanceWith(tTooLargeFilesWithNoConflictingFiles);
      },
      tearDown: () {
        File('some_file.txt').deleteSync();
      },
      act: (cubit) async {
        await cubit.startUploadPreparation();
        await cubit.prepareUploadPlanAndCostEstimates();
      },
      expect: () => <dynamic>[
        UploadPreparationInitialized(),
        TypeMatcher<UploadPreparationInProgress>(),
        UploadFileTooLarge(
            hasFilesToUpload: false,
            tooLargeFileNames: [tTooLargeFiles.first.name],
            isPrivate: false)
      ],
    );

    blocTest<UploadCubit, UploadState>(
      'should emit UploadReady when we have too large files but at least a not too large'
      ' and select the UploadAction skipBigFiles to skip those ',
      setUp: () {
        when(() => mockProfileCubit!.isCurrentProfileArConnect())
            .thenAnswer((i) => Future.value(false));
      },
      build: () {
        return getUploadCubitInstanceWith(
            tNoConflictingFiles..add(tTooLargeFile));
      },
      act: (cubit) async {
        await cubit.startUploadPreparation();
        await cubit.prepareUploadPlanAndCostEstimates(
            uploadAction: UploadActions.SkipBigFiles);
      },
      expect: () => <dynamic>[
        UploadPreparationInitialized(),
        UploadPreparationInProgress(isArConnect: false),
        TypeMatcher<UploadReady>()
      ],
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
