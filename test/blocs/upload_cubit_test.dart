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

// TODO: Test prepareUploadPlanAndCostEstimates
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
  late List<XFile> allConflictingFiles;
  late List<XFile> someConflictingFiles;
  late List<XFile> noConflictingFiles;

  final wallet = getTestWallet();
  String? walletAddress;

  final keyBytes = Uint8List(32);
  fillBytesWithSecureRandom(keyBytes);

  setUpAll(() {
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

  setUp(() async {
    db = getTestDb();

    final _testFile = XFile('assets/config/dev.json');

    // the `addTestFilesToDb` will generate files with this path and name.
    final conflictingFile = XFile(tRootFolderId + '1');

    // Contains only conflicting files.
    allConflictingFiles = <XFile>[conflictingFile];

    /// This list contains conflicting and non conflicting files.
    someConflictingFiles = <XFile>[conflictingFile, XFile('dumb_test_path')];

    // This list doesn't has any conflicting files.
    //
    // We need a real file because in the UploadCubit we needs the size of the file.
    // to know if the file is `tooLargeFiles`.
    noConflictingFiles = <XFile>[_testFile];

    // Initialize mocks
    mockArweave = MockArweaveService();
    mockPst = MockPstService();
    mockDriveDao = db.driveDao;
    mockProfileCubit = MockProfileCubit();
    walletAddress = await wallet.getAddress();
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
  group('Testing checkConflictingFiles', () {
    setUp(() {
      when(() => mockProfileCubit!.state).thenReturn(
        ProfileLoggedIn(
          username: 'Test',
          password: '123',
          wallet: wallet,
          walletAddress: walletAddress!,
          walletBalance: BigInt.one,
          cipherKey: SecretKey(keyBytes),
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
      when(() => mockUploadPlanUtils.xfilesToUploadPlan(
              files: any(named: 'files'),
              cipherKey: any(named: 'cipherKey'),
              wallet: any(named: 'wallet'),
              conflictingFiles: any(named: 'conflictingFiles'),
              targetDrive: any(named: 'targetDrive'),
              folderEntry: any<FolderEntry>(named: 'folderEntry')))
          .thenAnswer((invocation) => Future.value(UploadPlan.create(
              v2FileUploadHandles: {}, dataItemUploadHandles: {})));
    });
    blocTest<UploadCubit, UploadState>(
        'Should emit UploadFileConflict with correctly file names and'
        'isAllFilesConflicting true',
        build: () {
          return getUploadCubitInstanceWith(allConflictingFiles);
        },
        act: (cubit) async {
          await cubit.initializeCubit();
          await cubit.checkConflictingFiles();
        },
        tearDown: () async {
          await db.close();
        },
        expect: () => <dynamic>[
              TypeMatcher<UploadCubitInitialized>(),
              TypeMatcher<UploadPreparationInProgress>(),
              UploadFileConflict(
                  isAllFilesConflicting: true,
                  conflictingFileNames: [tRootFolderId + '1']),
            ]);

    blocTest<UploadCubit, UploadState>(
        'Should emit UploadFileConflict with correctly file names '
        'and isAllFilesConflicting false',
        build: () {
          return getUploadCubitInstanceWith(someConflictingFiles);
        },
        tearDown: () async {
          await db.close();
        },
        act: (cubit) async {
          await cubit.initializeCubit();
          await cubit.checkConflictingFiles();
        },
        expect: () => <dynamic>[
              TypeMatcher<UploadCubitInitialized>(),
              TypeMatcher<UploadPreparationInProgress>(),
              UploadFileConflict(
                  isAllFilesConflicting: false,
                  conflictingFileNames: [tRootFolderId + '1'])
            ]);

    blocTest<UploadCubit, UploadState>(
        'Emits [UploadCubitInitialized,UploadPreparationInProgress, UploadReady] when there arent conflicting files.',
        build: () {
          return getUploadCubitInstanceWith(noConflictingFiles);
        },
        tearDown: () async {
          await db.close();
        },
        act: (cubit) async {
          await cubit.initializeCubit();
          await cubit.checkConflictingFiles();
        },
        expect: () => <dynamic>[
              TypeMatcher<UploadCubitInitialized>(),
              TypeMatcher<UploadPreparationInProgress>(),
              TypeMatcher<UploadReady>()
            ]);
  });
}
