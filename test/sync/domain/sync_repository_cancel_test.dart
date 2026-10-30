import 'dart:async';

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_cancellation_token.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class _MockSnapshotValidationService extends Mock
    implements SnapshotValidationService {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class _MockWallet extends Mock implements Wallet {}

/// Stop, pressed during a full sync, through the real repository over a real
/// database with only the gateway mocked.
///
/// One drive finishes before the stop; the other is in the middle of a batch
/// of metadata reads when it comes. The run has to end at once rather than
/// when that batch would have, and leave both drives in a state the next sync
/// can build on.
void main() {
  const owner = 'owner-address';
  const finished = 'drive-finished';
  const stopped = 'drive-stopped';
  const ghostParent = 'folder-never-read';
  const currentHeight = 100;
  const oldHeight = 50;

  late Database db;
  late MockArweaveService arweave;
  late _MockWallet wallet;
  late SyncRepository syncRepository;

  /// Completes when the stopped drive's batch has started reading metadata.
  late Completer<void> stoppedBatchStarted;

  /// How many metadata batches were started for the stopped drive.
  late int stoppedBatches;

  DriveEntityHistoryTransactionModel transaction(String driveId, int height) =>
      DriveEntityHistoryTransactionModel(
        transactionCommonMixin:
            DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
                .fromJson({
          'id': '$driveId-tx-$height',
          'owner': {'address': owner},
          'tags': <dynamic>[],
          'block': {'height': height, 'timestamp': height * 100},
        }),
        cursor: 'cursor-$height',
      );

  FolderEntity root(String driveId) => FolderEntity(
        id: '$driveId-root',
        driveId: driveId,
        name: 'root',
      )
        ..txId = 'metadata-$driveId-root'
        ..ownerAddress = owner
        ..createdAt = DateTime(2026, 10, 29);

  FileEntity file(String driveId, String id, {required String parent}) =>
      FileEntity(
        id: id,
        driveId: driveId,
        parentFolderId: parent,
        name: id,
        size: 1,
        lastModifiedDate: DateTime(2026, 10, 29),
        dataTxId: 'data-$id',
        dataContentType: 'text/plain',
      )
        ..txId = 'metadata-$id'
        ..ownerAddress = owner
        ..createdAt = DateTime(2026, 10, 29);

  Future<void> insertDrive(String id) => db.into(db.drives).insert(
        DrivesCompanion.insert(
          id: id,
          name: id,
          ownerAddress: owner,
          rootFolderId: '$id-root',
          privacy: DrivePrivacyTag.public,
          lastBlockHeight: const Value(oldHeight),
        ),
      );

  setUp(() async {
    db = getTestDb();
    arweave = MockArweaveService();
    wallet = _MockWallet();
    final configService = MockConfigService();
    final userPreferences = _MockUserPreferencesRepository();
    stoppedBatchStarted = Completer<void>();
    stoppedBatches = 0;

    when(() => wallet.getAddress()).thenAnswer((_) async => owner);
    when(() => configService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      enableSyncFromSnapshot: false,
    ));
    when(() => arweave.getCurrentBlockHeight())
        .thenAnswer((_) async => currentHeight);
    when(() => arweave.clearUserDriveTxsCache()).thenReturn(null);
    when(() => arweave.snapshotMetadataHits).thenReturn(<String, int>{});
    when(() => arweave.snapshotMetadataMisses).thenReturn(<String, int>{});
    when(() => arweave.probeActiveDriveIds(
          driveIds: any(named: 'driveIds'),
          minBlockHeight: any(named: 'minBlockHeight'),
          ownerAddress: any(named: 'ownerAddress'),
        )).thenAnswer((_) async => (
          activeDriveIds: {finished, stopped},
          isComplete: true,
        ));
    when(() => arweave.getSegmentedTransactionsFromDrive(
          any(),
          ownerAddress: any(named: 'ownerAddress'),
          minBlockHeight: any(named: 'minBlockHeight'),
          maxBlockHeight: any(named: 'maxBlockHeight'),
          strategy: any(named: 'strategy'),
        )).thenAnswer((invocation) {
      final driveId = invocation.positionalArguments.first as String;
      return Stream.value([transaction(driveId, 60), transaction(driveId, 61)]);
    });
    when(() => arweave.createDriveEntityHistoryFromTransactions(
          any(),
          any(),
          any(),
          driveId: any(named: 'driveId'),
          ownerAddress: any(named: 'ownerAddress'),
          currentBlockHeight: any(named: 'currentBlockHeight'),
          onEntityFetched: any(named: 'onEntityFetched'),
          cancellationToken: any(named: 'cancellationToken'),
        )).thenAnswer((invocation) async {
      final driveId = invocation.namedArguments[#driveId] as String;
      if (driveId == finished) {
        // Its root, and a file in a folder whose own metadata never turns up:
        // the folder becomes a ghost.
        final block = BlockEntities(60)
          ..entities = [
            root(finished),
            file(finished, 'kept', parent: ghostParent),
          ];
        return DriveEntityHistory(60, [block]);
      }

      // The stopped drive's batch: the reads are slow, and go on until the
      // stop - as the real pool does, which takes no new read once the token
      // is cancelled and throws rather than hand back half a batch.
      stoppedBatches++;
      final token = invocation.namedArguments[#cancellationToken]
          as SyncCancellationToken?;
      if (!stoppedBatchStarted.isCompleted) stoppedBatchStarted.complete();
      if (token == null) {
        // Not told about the stop: the batch runs to its end, which for a
        // real one is a hundred or more round trips away.
        await Completer<void>().future;
      }
      await token!.onCancelled.first;
      throw SyncCancelledException();
    });
    when(() => userPreferences.saveUserHasHiddenItem(any()))
        .thenAnswer((_) async {});

    await insertDrive(finished);
    await insertDrive(stopped);

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

  /// Runs a full sync, stops it once [finished] is done and [stopped] is
  /// reading, and hands back what the run reported.
  Future<({List<SyncProgress> progress, List<Object> errors})>
      syncAndStop() async {
    final token = SyncCancellationToken();
    final progress = <SyncProgress>[];
    final errors = <Object>[];
    final ended = Completer<void>();
    final finishedDone = Completer<void>();

    syncRepository
        .syncAllDrives(wallet: wallet, cancellationToken: token)
        .listen(
      (p) {
        progress.add(p);
        if (p.syncedDriveIds.contains(finished) && !finishedDone.isCompleted) {
          finishedDone.complete();
        }
      },
      onError: errors.add,
      onDone: ended.complete,
    );

    await Future.wait([stoppedBatchStarted.future, finishedDone.future])
        .timeout(const Duration(seconds: 5));
    token.cancel();

    // Promptly: the stopped drive's batch was waiting on reads that would
    // otherwise have run to its end.
    await ended.future.timeout(const Duration(seconds: 2));
    return (progress: progress, errors: errors);
  }

  test('a stop mid-batch ends the run as cancelled, promptly', () async {
    final result = await syncAndStop();

    expect(result.errors, [isA<SyncCancelledException>()]);
    expect(result.progress.last.syncedDriveIds, [finished]);
  });

  test('nothing keeps running after the run has ended', () async {
    await syncAndStop();
    final batches = stoppedBatches;

    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(stoppedBatches, batches,
        reason: 'the stopped drive started another batch after the stop');
    verifyNever(() => arweave.getTransactionConfirmations(
          any(),
          owner: any(named: 'owner'),
          ownersByTxId: any(named: 'ownersByTxId'),
          ownerOverrides: any(named: 'ownerOverrides'),
          verifiedSink: any(named: 'verifiedSink'),
        ));
  });

  test(
      'the drive that finished keeps its data, its watermark and its ghost '
      'folder', () async {
    await syncAndStop();

    final drive = await db.driveDao.driveById(driveId: finished).getSingle();
    expect(drive.lastBlockHeight, currentHeight);
    expect(
      await db.driveDao.fileById(fileId: 'kept').getSingleOrNull(),
      isNotNull,
    );
    // The next sync starts above the file that called for this folder, so it
    // would never be made again.
    final ghost =
        await db.driveDao.folderById(folderId: ghostParent).getSingleOrNull();
    expect(ghost, isNotNull);
    expect(ghost!.isGhost, isTrue);
  });

  // The window between a drive raising its watermark and being counted as
  // synced. A stop there still leaves a finished drive: the next sync starts
  // above the file that called for the ghost.
  test(
      'a drive stopped just after it raised its watermark keeps its ghost '
      'folder too', () async {
    final token = SyncCancellationToken();
    final errors = <Object>[];
    final ended = Completer<void>();

    syncRepository
        .syncAllDrives(
          wallet: wallet,
          cancellationToken: token,
          onlyDriveIds: [finished],
          // Called right after the watermark is written.
          txFechedCallback: (driveId, _) => token.cancel(),
        )
        .listen((_) {}, onError: errors.add, onDone: ended.complete);
    await ended.future.timeout(const Duration(seconds: 2));

    expect(errors, [isA<SyncCancelledException>()]);
    final drive = await db.driveDao.driveById(driveId: finished).getSingle();
    expect(drive.lastBlockHeight, currentHeight);
    final ghost =
        await db.driveDao.folderById(folderId: ghostParent).getSingleOrNull();
    expect(ghost?.isGhost, isTrue);
  });

  test('the drive that was stopped is left for the next sync to redo',
      () async {
    await syncAndStop();

    final drive = await db.driveDao.driveById(driveId: stopped).getSingle();
    expect(drive.lastBlockHeight, oldHeight,
        reason: 'a raised watermark would skip what the stop left unread');
    expect(
      await db.driveDao.folderById(folderId: '$stopped-root').getSingleOrNull(),
      isNull,
      reason: 'nothing of the stopped batch was written',
    );
  });
}
