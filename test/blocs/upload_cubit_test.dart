import 'dart:io';
import 'dart:typed_data';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/upload_plan.dart';
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
  late List<XFile> tAllConflictingFiles;
  late List<XFile> tSomeConflictingFiles;
  late List<XFile> tNoConflictingFiles;

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
    final _tRealPathFile = XFile('assets/config/dev.json');

    // The `addTestFilesToDb` will generate files with this path and name, so it
    // will be a confliting file.
    final tConflictingFile = XFile(tRootFolderId + '1');

    // Contains only conflicting files.
    tAllConflictingFiles = <XFile>[tConflictingFile];

    /// This list contains conflicting and non conflicting files.
    tSomeConflictingFiles = <XFile>[tConflictingFile, XFile('dumb_test_path')];

    tNoConflictingFiles = <XFile>[_tRealPathFile];

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

  UploadCubit getUploadCubitInstanceWith(List<XFile> files) {
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

  void setDumbUploadPlan() => when(() => mockUploadPlanUtils.xfilesToUploadPlan(
      files: any(named: 'files'),
      cipherKey: any(named: 'cipherKey'),
      wallet: any(named: 'wallet'),
      conflictingFiles: any(named: 'conflictingFiles'),
      targetDrive: any(named: 'targetDrive'),
      folderEntry: any<FolderEntry>(
          named: 'folderEntry'))).thenAnswer((invocation) => Future.value(
      UploadPlan.create(v2FileUploadHandles: {}, dataItemUploadHandles: {})));

  group('Testing checkConflictingFiles', () {
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
        'Should emit UploadFileConflict with correctly file names and'
        ' isAllFilesConflicting true',
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
                  isAllFilesConflicting: true,
                  conflictingFileNames: [tRootFolderId + '1']),
            ]);

    blocTest<UploadCubit, UploadState>(
        'Should emit UploadFileConflict with correctly file names '
        'and isAllFilesConflicting false',
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
                  isAllFilesConflicting: false,
                  conflictingFileNames: [tRootFolderId + '1'])
            ]);

    blocTest<UploadCubit, UploadState>(
        'Emits [UploadCubitInitialized,UploadPreparationInProgress, UploadReady]'
        ' when there arent conflicting files.',
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

  group('Testing prepareUploadPlanAndCostEstimates', () {
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
    });
    blocTest<UploadCubit, UploadState>(
      'Should emit [UploadPreparationInitialized, UploadWalledMismatch]',
      setUp: () async {
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

    blocTest<UploadCubit, UploadState>(
      'Should emit'
      '[UploadPreparationInitialized, UploadPreparationInProgress(isArConnected: true), UploadReady]',
      setUp: () async {
        // wallet doesn't mismatch
        when(() => mockProfileCubit!.checkIfWalletMismatch())
            .thenAnswer((i) => Future.value(false));
        // is ArConnect profile
        when(() => mockProfileCubit!.isCurrentProfileArConnect())
            .thenAnswer((i) => Future.value(true));
        when(() => mockPst.getPSTFee(BigInt.zero))
            .thenAnswer((invocation) => Future.value(BigInt.zero));
        when(() => mockArweave.getArUsdConversionRate())
            .thenAnswer((invocation) => Future.value(10));

        when(() => mockUploadPlanUtils.xfilesToUploadPlan(
                files: any(named: 'files'),
                cipherKey: any(named: 'cipherKey'),
                wallet: any(named: 'wallet'),
                conflictingFiles: any(named: 'conflictingFiles'),
                targetDrive: any(named: 'targetDrive'),
                folderEntry: any<FolderEntry>(named: 'folderEntry')))
            .thenAnswer((invocation) => Future.value(UploadPlan.create(
                v2FileUploadHandles: {}, dataItemUploadHandles: {})));
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
        UploadPreparationInProgress(isArConnect: true),
        TypeMatcher<UploadReady>()
      ],
    );

    blocTest<UploadCubit, UploadState>(
      'Should emit'
      ' [UploadPreparationInitialized, UploadPreparationInProgress(isArConnected: false), UploadReady]',
      setUp: () async {
        // wallet doesn't mismatch
        when(() => mockProfileCubit!.checkIfWalletMismatch())
            .thenAnswer((i) => Future.value(false));

        // is not ArConnect profile
        when(() => mockProfileCubit!.isCurrentProfileArConnect())
            .thenAnswer((i) => Future.value(false));
        when(() => mockPst.getPSTFee(BigInt.zero))
            .thenAnswer((invocation) => Future.value(BigInt.zero));
        when(() => mockArweave.getArUsdConversionRate())
            .thenAnswer((invocation) => Future.value(10));

        when(() => mockUploadPlanUtils.xfilesToUploadPlan(
                files: any(named: 'files'),
                cipherKey: any(named: 'cipherKey'),
                wallet: any(named: 'wallet'),
                conflictingFiles: any(named: 'conflictingFiles'),
                targetDrive: any(named: 'targetDrive'),
                folderEntry: any<FolderEntry>(named: 'folderEntry')))
            .thenAnswer((invocation) => Future.value(UploadPlan.create(
                v2FileUploadHandles: {}, dataItemUploadHandles: {})));
      },
      build: () {
        return getUploadCubitInstanceWith(tNoConflictingFiles);
      },
      act: (cubit) async {
        await cubit.startUploadPreparation();
        await cubit.prepareUploadPlanAndCostEstimates();
      },
      tearDown: () {
        getUploadCubitInstanceWith(tNoConflictingFiles).close();
      },
      expect: () => <dynamic>[
        UploadPreparationInitialized(),
        UploadPreparationInProgress(isArConnect: false),
        TypeMatcher<UploadReady>()
      ],
    );

    late XFile tTooLargeFile;
    late List<XFile> tTooLargeFiles;

    blocTest<UploadCubit, UploadState>(
      'Should emit'
      '[UploadPreparationInitialized, UploadPreparationInProgress(isArConnected: false), UploadFileTooLarge]',
      setUp: () async {
        final file = File('some_file.txt');

        file.writeAsBytesSync(Uint8List(publicFileSizeLimit.toInt() + 1));

        tTooLargeFile = XFile(file.path);

        tTooLargeFiles = [tTooLargeFile];
        // wallet doesn't mismatch
        when(() => mockProfileCubit!.checkIfWalletMismatch())
            .thenAnswer((i) => Future.value(false));
        // is not ArConnect profile
        when(() => mockProfileCubit!.isCurrentProfileArConnect())
            .thenAnswer((i) => Future.value(false));
        when(() => mockPst.getPSTFee(BigInt.zero))
            .thenAnswer((invocation) => Future.value(BigInt.zero));
        when(() => mockArweave.getArUsdConversionRate())
            .thenAnswer((invocation) => Future.value(10));
        when(() => mockUploadPlanUtils.xfilesToUploadPlan(
                files: any(named: 'files'),
                cipherKey: any(named: 'cipherKey'),
                wallet: any(named: 'wallet'),
                conflictingFiles: any(named: 'conflictingFiles'),
                targetDrive: any(named: 'targetDrive'),
                folderEntry: any<FolderEntry>(named: 'folderEntry')))
            .thenAnswer((invocation) => Future.value(UploadPlan.create(
                v2FileUploadHandles: {}, dataItemUploadHandles: {})));
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
        UploadPreparationInProgress(isArConnect: false),
        UploadFileTooLarge(
            tooLargeFileNames: [tTooLargeFiles.first.name], isPrivate: false)
      ],
    );
  });
}
