import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:platform/platform.dart';
import 'package:uuid/uuid.dart';

import '../test_utils/utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FsEntryMoveBloc', () {
    late Database db;
    late DriveDao driveDao;
    late ArweaveService arweave;
    late TurboService turboService;

    late ProfileCubit profileCubit;
    late SyncCubit syncBloc;
    final driveId = const Uuid().v4();
    final rootFolderId = const Uuid().v4();
    final nestedFolderId = const Uuid().v4();
    final conflictTestFolderId = const Uuid().v4();
    const rootFolderFileCount = 3;

    setUp(() async {
      registerFallbackValue(
        await getTestTransaction('test/fixtures/signed_v2_tx.json'),
      );
      registerFallbackValue(
        await getTestDataItem('test/fixtures/signed_v2_tx.json'),
      );
      registerFallbackValue(FileEntity());
      registerFallbackValue(Wallet());

      db = getTestDb();
      await db.batch((batch) {
        // Default date
        final defaultDate = DateTime(2017, 9, 7, 17, 30);
        // Create fake drive for test
        batch.insert(
          db.drives,
          DrivesCompanion.insert(
            id: driveId,
            rootFolderId: rootFolderId,
            ownerAddress: 'fake-owner-address',
            name: 'fake-drive-name',
            privacy: DrivePrivacy.public,
          ),
        );
        // Create fake root folder for drive and sub folders
        batch.insertAll(db.folderEntries, [
          FolderEntriesCompanion.insert(
              id: rootFolderId,
              driveId: driveId,
              name: 'fake-drive-name',
              path: ''),
          FolderEntriesCompanion.insert(
              id: nestedFolderId,
              driveId: driveId,
              parentFolderId: Value(rootFolderId),
              name: nestedFolderId,
              path: '/$nestedFolderId'),
          FolderEntriesCompanion.insert(
              id: conflictTestFolderId,
              driveId: driveId,
              parentFolderId: Value(rootFolderId),
              name: conflictTestFolderId,
              path: '/$conflictTestFolderId'),
        ]);
        // Insert fake files
        batch.insertAll(
          db.fileEntries,
          [
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$rootFolderId$i';
                return FileEntriesCompanion.insert(
                  id: fileId,
                  driveId: driveId,
                  parentFolderId: rootFolderId,
                  name: fileId,
                  path: '/$fileId',
                  dataTxId: '${fileId}Data',
                  size: 500,
                  dateCreated: Value(defaultDate),
                  lastModifiedDate: defaultDate,
                  dataContentType: const Value(''),
                );
              },
            ),
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$conflictTestFolderId$i';
                return FileEntriesCompanion.insert(
                  id: fileId,
                  driveId: driveId,
                  parentFolderId: conflictTestFolderId,
                  name: fileId,
                  path: '/$fileId',
                  dataTxId: '${fileId}Data',
                  size: 500,
                  dateCreated: Value(defaultDate),
                  lastModifiedDate: defaultDate,
                  dataContentType: const Value(''),
                );
              },
            ),
          ],
        );
        // Insert fake file revisions
        batch.insertAll(
          db.fileRevisions,
          [
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$rootFolderId$i';
                return FileRevisionsCompanion.insert(
                  fileId: fileId,
                  driveId: driveId,
                  parentFolderId: rootFolderId,
                  name: fileId,
                  metadataTxId: '${fileId}Meta',
                  action: RevisionAction.create,
                  dataTxId: '${fileId}Data',
                  size: 500,
                  dateCreated: Value(defaultDate),
                  lastModifiedDate: defaultDate,
                  dataContentType: const Value(''),
                );
              },
            ),
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$conflictTestFolderId$i';
                return FileRevisionsCompanion.insert(
                  fileId: fileId,
                  driveId: driveId,
                  parentFolderId: conflictTestFolderId,
                  name: fileId,
                  metadataTxId: '${fileId}Meta',
                  action: RevisionAction.create,
                  dataTxId: '${fileId}Data',
                  size: 500,
                  dateCreated: Value(defaultDate),
                  lastModifiedDate: defaultDate,
                  dataContentType: const Value(''),
                );
              },
            ),
          ],
        );
        // Insert fake metadata and data transactions
        batch.insertAll(
          db.networkTransactions,
          [
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$rootFolderId$i';
                return NetworkTransactionsCompanion.insert(
                  id: '${fileId}Meta',
                  status: const Value(TransactionStatus.confirmed),
                  dateCreated: Value(defaultDate),
                );
              },
            ),
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$rootFolderId$i';
                return NetworkTransactionsCompanion.insert(
                  id: '${fileId}Data',
                  status: const Value(TransactionStatus.confirmed),
                  dateCreated: Value(defaultDate),
                );
              },
            ),
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$conflictTestFolderId$i';
                return NetworkTransactionsCompanion.insert(
                  id: '${fileId}Meta',
                  status: const Value(TransactionStatus.confirmed),
                  dateCreated: Value(defaultDate),
                );
              },
            ),
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$conflictTestFolderId$i';
                return NetworkTransactionsCompanion.insert(
                  id: '${fileId}Data',
                  status: const Value(TransactionStatus.confirmed),
                  dateCreated: Value(defaultDate),
                );
              },
            ),
          ],
        );
      });

      driveDao = db.driveDao;
      AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);
      arweave = MockArweaveService();
      when(() => arweave.postTx(any())).thenAnswer((_) async => Future.value());
      when(() => arweave.prepareEntityDataItem(any(), any(),
          key: any(named: 'key'))).thenAnswer(
        (_) async => await getTestDataItem('test/fixtures/signed_v2_tx.json'),
      );
      turboService = MockTurboService();
      when(() => turboService.postDataItem(dataItem: any(named: 'dataItem')))
          .thenAnswer(
        (_) async => Future.value(),
      );
      syncBloc = MockSyncBloc();
      when(() => syncBloc.generateFsEntryPaths(any(), any(), any())).thenAnswer(
        (_) async => Future.value(),
      );
      profileCubit = MockProfileCubit();

      final keyBytes = Uint8List(32);
      fillBytesWithSecureRandom(keyBytes);
      final wallet = getTestWallet();
      when(profileCubit.logoutIfWalletMismatch)
          .thenAnswer((_) => Future.value(false));
      PackageInfo.setMockInitialValues(
        appName: 'fake-app-name',
        packageName: 'fake-package-name',
        version: 'fake-version',
        buildNumber: 'fake-build-number',
        buildSignature: 'fake-build-signature',
      );

      when(() => profileCubit.state).thenReturn(
        ProfileLoggedIn(
          username: '',
          password: '123',
          wallet: wallet,
          cipherKey: SecretKey(keyBytes),
          walletAddress: await wallet.getAddress(),
          walletBalance: BigInt.one,
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });
    blocTest(
      'throws when selectedItems is empty',
      build: () => FsEntryMoveBloc(
        arweave: arweave,
        turboService: turboService,
        syncCubit: syncBloc,
        driveId: driveId,
        driveDao: driveDao,
        profileCubit: profileCubit,
        selectedItems: [],
      ),
      errors: () => [isA<Exception>()],
    );
    late List<SelectedItem> selectedItems;
    blocTest(
      'successfully moves files into folders when there are no conflicts',
      setUp: (() async {
        final fileRevisions = await driveDao
            .filesInFolderAtPathWithRevisionTransactions(
              driveId: driveId,
              path: '',
            )
            .get();
        selectedItems = [
          ...fileRevisions.map((f) => SelectedFile(file: f)),
        ];
      }),
      build: () => FsEntryMoveBloc(
        arweave: arweave,
        turboService: turboService,
        syncCubit: syncBloc,
        driveId: driveId,
        driveDao: driveDao,
        profileCubit: profileCubit,
        selectedItems: selectedItems,
        platform: FakePlatform(operatingSystem: 'android'),
      ),
      act: (FsEntryMoveBloc bloc) async {
        bloc.add(FsEntryMoveUpdateTargetFolder(folderId: nestedFolderId));
        await Future.delayed(const Duration(seconds: 2));
        if (bloc.state is FsEntryMoveLoadSuccess) {
          bloc.add(FsEntryMoveSubmit(
            folderInView:
                (bloc.state as FsEntryMoveLoadSuccess).viewingFolder.folder,
          ));
        }
      },
      wait: const Duration(seconds: 4),
      expect: () => [
        isA<FsEntryMoveLoadSuccess>(),
        isA<FsEntryMoveLoadInProgress>(),
        isA<FsEntryMoveSuccess>(),
      ],
    );
  });
}
