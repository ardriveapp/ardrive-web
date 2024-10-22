import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:platform/platform.dart';
import 'package:uuid/uuid.dart';

import '../test_utils/utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FsEntryMoveBloc', () {
    late Database db;
    late DriveDao driveDao;
    late ArweaveService arweave;
    late TurboUploadService turboUploadService;

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
      registerFallbackValue(DataBundle(blob: Uint8List(0)));
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
            privacy: DrivePrivacyTag.public,
          ),
        );
        // Create fake root folder for drive and sub folders
        batch.insertAll(db.folderEntries, [
          FolderEntriesCompanion.insert(
            id: rootFolderId,
            driveId: driveId,
            name: 'fake-drive-name',
            isHidden: const Value(false),
            path: '',
          ),
          FolderEntriesCompanion.insert(
            id: nestedFolderId,
            driveId: driveId,
            parentFolderId: Value(rootFolderId),
            name: nestedFolderId,
            isHidden: const Value(false),
            path: '',
          ),
          FolderEntriesCompanion.insert(
            id: conflictTestFolderId,
            driveId: driveId,
            parentFolderId: Value(rootFolderId),
            name: conflictTestFolderId,
            isHidden: const Value(false),
            path: '',
          ),
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
                  dataTxId: '${fileId}Data',
                  size: 500,
                  dateCreated: Value(defaultDate),
                  lastModifiedDate: defaultDate,
                  dataContentType: const Value(''),
                  isHidden: const Value(false),
                  path: '',
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
                  dataTxId: '${fileId}Data',
                  size: 500,
                  dateCreated: Value(defaultDate),
                  lastModifiedDate: defaultDate,
                  dataContentType: const Value(''),
                  isHidden: const Value(false),
                  path: '',
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
                  isHidden: const Value(false),
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
                  isHidden: const Value(false),
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
      when(() => arweave.prepareDataBundleTx(any(), any())).thenAnswer(
        (_) async =>
            await getTestTransaction('test/fixtures/signed_v2_tx.json'),
      );
      turboUploadService = DontUseUploadService();
      syncBloc = MockSyncBloc();

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
          user: User(
            password: '123',
            wallet: wallet,
            cipherKey: SecretKey(keyBytes),
            walletAddress: await wallet.getAddress(),
            walletBalance: BigInt.one,
            profileType: ProfileType.json,
            ioTokens: 'ioTokens',
            errorFetchingIOTokens: false,
          ),
          useTurbo: false,
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
        turboUploadService: turboUploadService,
        syncCubit: syncBloc,
        driveId: driveId,
        driveDao: driveDao,
        profileCubit: profileCubit,
        selectedItems: [],
        crypto: ArDriveCrypto(),
      ),
      errors: () => [isA<Exception>()],
    );
    blocTest(
      'successfully moves files into folders when there are no conflicts',
      build: () => FsEntryMoveBloc(
        crypto: ArDriveCrypto(),
        arweave: arweave,
        turboUploadService: turboUploadService,
        syncCubit: syncBloc,
        driveId: driveId,
        driveDao: driveDao,
        profileCubit: profileCubit,
        // TODO: revisit this when we have a better way to mock the selected items
        selectedItems: [],
        platform: FakePlatform(operatingSystem: 'android'),
      ),
      act: (FsEntryMoveBloc bloc) async {
        bloc.add(FsEntryMoveUpdateTargetFolder(folderId: nestedFolderId));
        await Future.delayed(const Duration(seconds: 2));
        if (bloc.state is FsEntryMoveLoadSuccess) {
          bloc.add(FsEntryMoveSubmit(
            folderInView:
                (bloc.state as FsEntryMoveLoadSuccess).viewingFolder.folder,
            showHiddenItems: false,
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
