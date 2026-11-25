import 'package:ardrive/blocs/constants.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/models/enums.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class _MockSnapshotValidationService extends Mock
    implements SnapshotValidationService {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class _MockWallet extends Mock implements Wallet {}

/// "Sync this drive" settles the drive's pending changes, not only its
/// uploads' data.
///
/// Publish waits while any metadata of the drive (the drive, a folder, a
/// file: an upload, a rename, a move) is pending, and its "Sync this drive"
/// runs a single-drive sync. That sync re-checked only the drive's file data
/// transactions, so a page blocked on metadata stayed blocked until the next
/// full sync. Real repository, real in-memory database; only the gateway is a
/// fake, and it says every transaction asked about is mined.
void main() {
  const driveId = 'drive-id';
  const otherDriveId = 'other-drive-id';
  const ownerAddress = 'owner-address';
  const rootFolderId = 'root-folder-id';
  const fileId = 'file-id';

  const driveMeta = 'drive-meta-tx';
  const folderMeta = 'folder-meta-tx';
  const fileMeta = 'file-meta-tx';
  const fileData = 'file-data-tx';
  const otherDriveMeta = 'other-drive-meta-tx';

  late Database db;
  late MockArweaveService arweave;
  late SyncRepository syncRepository;
  late _MockWallet wallet;
  late List<String> askedAbout;

  Future<String> statusOf(String id) async =>
      (await (db.select(db.networkTransactions)..where((t) => t.id.equals(id)))
              .getSingle())
          .status;

  setUp(() async {
    db = getTestDb();
    arweave = MockArweaveService();
    wallet = _MockWallet();
    askedAbout = [];
    final configService = MockConfigService();
    final userPreferences = _MockUserPreferencesRepository();

    when(() => wallet.getAddress()).thenAnswer((_) async => ownerAddress);
    when(() => configService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      enableSyncFromSnapshot: false,
    ));
    when(() => arweave.getCurrentBlockHeight()).thenAnswer((_) async => 100);
    when(() => arweave.clearUserDriveTxsCache()).thenReturn(null);
    when(() => arweave.snapshotMetadataHits).thenReturn(<String, int>{});
    when(() => arweave.snapshotMetadataMisses).thenReturn(<String, int>{});
    when(() => arweave.getSegmentedTransactionsFromDrive(
          any(),
          ownerAddress: any(named: 'ownerAddress'),
          minBlockHeight: any(named: 'minBlockHeight'),
          maxBlockHeight: any(named: 'maxBlockHeight'),
          strategy: any(named: 'strategy'),
        )).thenAnswer((_) => const Stream.empty());
    when(() => arweave.getTransactionConfirmations(
          any(),
          owner: any(named: 'owner'),
          ownersByTxId: any(named: 'ownersByTxId'),
          ownerOverrides: any(named: 'ownerOverrides'),
          verifiedSink: any(named: 'verifiedSink'),
        )).thenAnswer((i) async {
      final ids = (i.positionalArguments.first as List).cast<String>();
      askedAbout.addAll(ids);
      return {for (final id in ids) id: kRequiredTxConfirmationCount};
    });
    when(() => userPreferences.load()).thenAnswer(
      (_) async => const UserPreferences(
        currentTheme: ArDriveThemes.light,
        lastSelectedDriveId: null,
      ),
    );
    when(() => userPreferences.saveUserHasHiddenItem(any()))
        .thenAnswer((_) async {});

    await db.driveDao.insertNewNetworkTransactions([
      for (final id in [driveMeta, folderMeta, fileMeta, fileData])
        NetworkTransactionsCompanion(
          id: Value(id),
          status: const Value(TransactionStatus.pending),
          dateCreated: Value(DateTime.now()),
        ),
      NetworkTransactionsCompanion(
        id: const Value(otherDriveMeta),
        status: const Value(TransactionStatus.pending),
        dateCreated: Value(DateTime.now()),
      ),
    ]);
    for (final (id, meta) in [
      (driveId, driveMeta),
      (otherDriveId, otherDriveMeta)
    ]) {
      await db.into(db.drives).insert(DrivesCompanion.insert(
            id: id,
            name: 'Drive',
            ownerAddress: ownerAddress,
            rootFolderId: '$id-root',
            privacy: DrivePrivacyTag.public,
            lastBlockHeight: const Value(50),
          ));
      await db.into(db.driveRevisions).insert(DriveRevisionsCompanion.insert(
            driveId: id,
            rootFolderId: '$id-root',
            name: 'Drive',
            privacy: DrivePrivacyTag.public,
            metadataTxId: meta,
            ownerAddress: ownerAddress,
            action: RevisionAction.create,
          ));
    }
    await db.into(db.folderRevisions).insert(FolderRevisionsCompanion.insert(
          folderId: rootFolderId,
          driveId: driveId,
          name: 'Drive',
          metadataTxId: folderMeta,
          action: RevisionAction.rename,
        ));
    await db.into(db.fileRevisions).insert(FileRevisionsCompanion.insert(
          fileId: fileId,
          driveId: driveId,
          parentFolderId: rootFolderId,
          name: 'a.txt',
          size: 1,
          lastModifiedDate: DateTime.now(),
          metadataTxId: fileMeta,
          dataTxId: fileData,
          action: RevisionAction.create,
        ));

    syncRepository = SyncRepository(
      arweave: arweave,
      driveDao: db.driveDao,
      configService: configService,
      batchProcessor: BatchProcessor(),
      snapshotValidationService: _MockSnapshotValidationService(),
      userPreferencesRepository: userPreferences,
    );
  });

  tearDown(() => db.close());

  test('settles the drive, folder and file metadata as well as the data',
      () async {
    await syncRepository
        .syncSingleDrive(driveId: driveId, wallet: wallet)
        .toList()
        .timeout(const Duration(seconds: 5));

    for (final id in [driveMeta, folderMeta, fileMeta, fileData]) {
      expect(await statusOf(id), TransactionStatus.confirmed, reason: id);
    }
  });

  test("leaves other drives' pending changes to their own sync", () async {
    await syncRepository
        .syncSingleDrive(driveId: driveId, wallet: wallet)
        .toList()
        .timeout(const Duration(seconds: 5));

    expect(askedAbout, isNot(contains(otherDriveMeta)));
    expect(await statusOf(otherDriveMeta), TransactionStatus.pending);
  });
}
