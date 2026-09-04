import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class _MockSnapshotValidationService extends Mock
    implements SnapshotValidationService {}

class _MockARNSRepository extends Mock implements ARNSRepository {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

/// A sync that writes N entities has to report N.
///
/// `SyncProgress.entitiesSynced` shipped as a number nothing in `lib/` ever
/// set: it was 0 in `initial()`, 0 in `emptySyncCompleted()`, and no `copyWith`
/// gave it a value - so a sync that pulled in five hundred files still told the
/// user "up to date, nothing new". Every test of the summary built its state by
/// hand, which is exactly how that got through, so this one drives the real
/// repository against a real database and reads the number off the far end.
void main() {
  const driveId = 'drive-id';
  const rootFolderId = 'root-folder-id';
  const ownerAddress = 'owner-address';

  late Database db;
  late MockArweaveService arweave;
  late MockConfigService configService;
  late _MockSnapshotValidationService snapshotValidation;
  late _MockARNSRepository arnsRepository;
  late _MockUserPreferencesRepository userPreferences;
  late SyncRepository syncRepository;

  /// The transactions the gateway hands back. Their contents do not matter:
  /// what they parse into is stubbed below, entity by entity.
  DriveEntityHistoryTransactionModel transactionAt(int height) {
    return DriveEntityHistoryTransactionModel(
      transactionCommonMixin:
          DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
              .fromJson({
        'id': 'tx-$height',
        'owner': {'address': ownerAddress},
        'tags': <dynamic>[],
        'block': {'height': height, 'timestamp': height * 100},
      }),
      cursor: 'cursor-$height',
    );
  }

  FolderEntity folder(String id, {String? parentFolderId}) => FolderEntity(
        id: id,
        driveId: driveId,
        parentFolderId: parentFolderId,
        name: id,
      )
        ..txId = 'metadata-$id'
        ..ownerAddress = ownerAddress
        ..createdAt = DateTime(2026, 8, 29);

  FileEntity file(String id, {String parentFolderId = rootFolderId}) =>
      FileEntity(
        id: id,
        driveId: driveId,
        parentFolderId: parentFolderId,
        name: id,
        size: 1024,
        lastModifiedDate: DateTime(2026, 8, 29),
        dataTxId: 'data-$id',
        dataContentType: 'text/plain',
      )
        ..txId = 'metadata-$id'
        ..ownerAddress = ownerAddress
        ..createdAt = DateTime(2026, 8, 29);

  /// What the gateway returns for this drive: one transaction per entity, and
  /// those entities when the sync asks what the transactions were.
  void gatewayReturns(List<Entity> entities) {
    when(() => arweave.getSegmentedTransactionsFromDrive(
          any(),
          ownerAddress: any(named: 'ownerAddress'),
          minBlockHeight: any(named: 'minBlockHeight'),
          maxBlockHeight: any(named: 'maxBlockHeight'),
          strategy: any(named: 'strategy'),
        )).thenAnswer((_) => Stream.value([
          for (var i = 0; i < entities.length; i++) transactionAt(10 + i),
        ]));

    when(() => arweave.createDriveEntityHistoryFromTransactions(
          any(),
          any(),
          any(),
          driveId: any(named: 'driveId'),
          ownerAddress: any(named: 'ownerAddress'),
          currentBlockHeight: any(named: 'currentBlockHeight'),
        )).thenAnswer((_) async {
      final block = BlockEntities(10)..entities = [...entities];
      return DriveEntityHistory(10, [block]);
    });
  }

  Future<void> insertDrive({int? lastBlockHeight}) async {
    await db.into(db.drives).insert(
          DrivesCompanion.insert(
            id: driveId,
            name: 'Test Drive',
            ownerAddress: ownerAddress,
            rootFolderId: rootFolderId,
            privacy: DrivePrivacyTag.public,
            lastBlockHeight: Value(lastBlockHeight),
          ),
        );
  }

  /// Runs a real single-drive sync to exhaustion and hands back the last
  /// thing it reported - the progress the cubit turns into a result.
  Future<SyncProgress> syncToCompletion() async {
    final emitted = <SyncProgress>[];
    await for (final progress in syncRepository.syncSingleDrive(
      driveId: driveId,
    )) {
      emitted.add(progress);
    }
    return emitted.last;
  }

  setUp(() {
    db = getTestDb();
    arweave = MockArweaveService();
    configService = MockConfigService();
    snapshotValidation = _MockSnapshotValidationService();
    arnsRepository = _MockARNSRepository();
    userPreferences = _MockUserPreferencesRepository();

    when(() => configService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      enableSyncFromSnapshot: false,
      autoSync: true,
    ));

    when(() => arweave.getCurrentBlockHeight()).thenAnswer((_) async => 100);
    when(() => arweave.clearUserDriveTxsCache()).thenReturn(null);
    when(() => arweave.snapshotMetadataHits).thenReturn(<String, int>{});
    when(() => arweave.snapshotMetadataMisses).thenReturn(<String, int>{});
    when(() => arweave.getTransactionConfirmations(
          any(),
          owner: any(named: 'owner'),
          ownersByTxId: any(named: 'ownersByTxId'),
          ownerOverrides: any(named: 'ownerOverrides'),
          verifiedSink: any(named: 'verifiedSink'),
        )).thenAnswer((_) async => <String?, int>{});
    when(() => arnsRepository.getAntRecordsForWallet(any(),
        update: any(named: 'update'))).thenAnswer((_) async => <ANTRecord>[]);
    when(() => userPreferences.load()).thenAnswer(
      (_) async => const UserPreferences(
        currentTheme: ArDriveThemes.light,
        lastSelectedDriveId: null,
      ),
    );
    when(() => userPreferences.saveUserHasHiddenItem(any()))
        .thenAnswer((_) async {});

    gatewayReturns([]);

    syncRepository = SyncRepository(
      arweave: arweave,
      driveDao: db.driveDao,
      configService: configService,
      batchProcessor: BatchProcessor(),
      snapshotValidationService: snapshotValidation,
      arnsRepository: arnsRepository,
      userPreferencesRepository: userPreferences,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('a sync that wrote nothing reports nothing', () async {
    await insertDrive();

    final result = await syncToCompletion();

    expect(result.entitiesSynced, 0);
    expect(await db.select(db.fileRevisions).get(), isEmpty);
  });

  test('a sync reports every file and folder revision it wrote', () async {
    await insertDrive();
    gatewayReturns([
      folder(rootFolderId),
      folder('subfolder', parentFolderId: rootFolderId),
      file('file-a'),
      file('file-b'),
      file('file-c'),
    ]);

    final result = await syncToCompletion();

    // What the database actually holds, so the reported number is checked
    // against the writes rather than against another count of the same guess.
    final folderRevisions = await db.select(db.folderRevisions).get();
    final fileRevisions = await db.select(db.fileRevisions).get();
    expect(folderRevisions, hasLength(2));
    expect(fileRevisions, hasLength(3));

    expect(result.entitiesSynced, 5);
  });

  test('a second sync over the same entities reports nothing new', () async {
    // Every sync rewinds its watermark and re-walks the last blocks, so the
    // same entities come back around unchanged. They were already written;
    // reporting them again would announce a drive full of new items on a sync
    // that wrote none.
    await insertDrive();
    gatewayReturns([folder(rootFolderId), file('file-a')]);

    expect((await syncToCompletion()).entitiesSynced, 2);

    final second = await syncToCompletion();

    expect(second.entitiesSynced, 0);
    expect(await db.select(db.fileRevisions).get(), hasLength(1));
  });

  test('a sync counts only what it wrote, not what came before it', () async {
    await insertDrive();
    gatewayReturns([folder(rootFolderId), file('file-a')]);
    await syncToCompletion();

    // One more file arrives on top of the two entities already in the drive.
    gatewayReturns([folder(rootFolderId), file('file-a'), file('file-b')]);

    final result = await syncToCompletion();

    expect(await db.select(db.fileRevisions).get(), hasLength(2));
    expect(result.entitiesSynced, 1);
  });

  test('a file that arrives with its history is one item, not one per version',
      () async {
    await insertDrive();

    // A first sync walks a drive's whole history, so one file can arrive with
    // several versions at once. That writes several revisions, but it is one
    // item to the person reading the summary - the difference between
    // counting revisions and counting entities.
    gatewayReturns([
      folder(rootFolderId),
      file('file-a'),
      file('file-a')
        ..name = 'file-a-v2'
        ..txId = 'metadata-file-a-v2'
        ..createdAt = DateTime(2026, 8, 30),
    ]);

    final result = await syncToCompletion();

    expect(await db.select(db.fileRevisions).get(), hasLength(2));
    // The root folder and the file. Counting revisions would say 3.
    expect(result.entitiesSynced, 2);
  });

  test('a changed file is a revision the sync reports', () async {
    await insertDrive();
    gatewayReturns([folder(rootFolderId), file('file-a')]);
    await syncToCompletion();

    gatewayReturns([
      folder(rootFolderId),
      file('file-a')
        ..name = 'file-a-renamed'
        ..txId = 'metadata-file-a-v2'
        ..createdAt = DateTime(2026, 8, 30),
    ]);

    final result = await syncToCompletion();

    expect(await db.select(db.fileRevisions).get(), hasLength(2));
    expect(result.entitiesSynced, 1);
  });
}
