part of 'package:ardrive/blocs/sync/sync_cubit.dart';

const fetchPhaseWeight = 0.1;
const parsePhaseWeight = 0.9;

Stream<double> _syncDrive(
  String driveId, {
  required DriveDao driveDao,
  required ProfileState profileState,
  required ArweaveService arweave,
  required Database database,
  required Function addError,
  required int currentBlockHeight,
  required int lastBlockHeight,
  required int transactionParseBatchSize,
  required Map<FolderID, GhostFolder> ghostFolders,
  required String ownerAddress,
  required ConfigService configService,
}) async* {
  /// Variables to count the current drive's progress information
  final drive = await driveDao.driveById(driveId: driveId).getSingle();
  final startSyncDT = DateTime.now();

  logSync('Syncing drive - ${drive.name}');

  SecretKey? driveKey;

  if (drive.isPrivate) {
    // Only sync private drives when the user is logged in.
    if (profileState is ProfileLoggedIn) {
      driveKey = await driveDao.getDriveKey(drive.id, profileState.cipherKey);
    } else {
      driveKey = await driveDao.getDriveKeyFromMemory(drive.id);
      if (driveKey == null) {
        throw StateError('Drive key not found');
      }
    }
  }
  final fetchPhaseStartDT = DateTime.now();

  logSync('Fetching all transactions for drive ${drive.name}\n');

  final transactions = <DriveHistoryTransaction>[];

  List<SnapshotItem> snapshotItems = [];

  if (configService.config.enableSyncFromSnapshot) {
    logger.i('Syncing from snapshot');

    final snapshotsStream = arweave.getAllSnapshotsOfDrive(
      driveId,
      lastBlockHeight,
      ownerAddress: ownerAddress,
    );

    snapshotItems = await SnapshotItem.instantiateAll(
      snapshotsStream,
      arweave: arweave,
    ).toList();
  }

  final SnapshotDriveHistory snapshotDriveHistory = SnapshotDriveHistory(
    items: snapshotItems,
  );

  final totalRangeToQueryFor = HeightRange(
    rangeSegments: [
      Range(
        start: lastBlockHeight,
        end: currentBlockHeight,
      ),
    ],
  );

  final HeightRange gqlDriveHistorySubRanges = HeightRange.difference(
    totalRangeToQueryFor,
    snapshotDriveHistory.subRanges,
  );

  final GQLDriveHistory gqlDriveHistory = GQLDriveHistory(
    subRanges: gqlDriveHistorySubRanges,
    arweave: arweave,
    driveId: driveId,
    ownerAddress: ownerAddress,
  );

  print('Total range to query for: ${totalRangeToQueryFor.rangeSegments}');
  print(
    'Sub ranges in snapshots (DRIVE ID: $driveId): ${snapshotDriveHistory.subRanges.rangeSegments}',
  );
  print(
    'Sub ranges in GQL (DRIVE ID: $driveId): ${gqlDriveHistorySubRanges.rangeSegments}',
  );

  final DriveHistoryComposite driveHistory = DriveHistoryComposite(
    subRanges: totalRangeToQueryFor,
    gqlDriveHistory: gqlDriveHistory,
    snapshotDriveHistory: snapshotDriveHistory,
  );
  final transactionsStream = driveHistory.getNextStream();

  final gqlNodesCache = await GQLNodesCache.fromCacheStore(
    await newSharedPreferencesCacheStore(),
  );

  /// The first block height of this drive.
  int? firstBlockHeight;

  /// In order to measure the sync progress by the block height, we use the difference
  /// between the first block and the `currentBlockHeight`
  late int totalBlockHeightDifference;

  /// This percentage is based on block heights.
  var fetchPhasePercentage = 0.0;

  /// First phase of the sync
  /// Here we get all transactions from its drive.
  await for (DriveHistoryTransaction t in transactionsStream) {
    double calculatePercentageBasedOnBlockHeights() {
      final block = t.block;

      if (block != null) {
        return (1 -
            ((currentBlockHeight - block.height) / totalBlockHeightDifference));
      }
      logSync(
        'The transaction block is null. \nTransaction node id: ${t.id}',
      );

      print('New fetch-phase percentage: $fetchPhasePercentage');

      /// if the block is null, we don't calculate and keep the same percentage
      return fetchPhasePercentage;
    }

    /// Initialize only once `firstBlockHeight` and `totalBlockHeightDifference`
    if (firstBlockHeight == null) {
      final block = t.block;

      if (block != null) {
        firstBlockHeight = block.height;
        totalBlockHeightDifference = currentBlockHeight - firstBlockHeight;
        print(
          'First height: $firstBlockHeight, totalHeightDiff: $totalBlockHeightDifference',
        );
      } else {
        logSync(
          'The transaction block is null. \nTransaction node id: ${t.id}',
        );
      }
    } else {
      print('Block attribute is already present - $firstBlockHeight');
    }

    print('Adding transaction ${t.id}');
    transactions.add(t);

    /// We can only calculate the fetch percentage if we have the `firstBlockHeight`
    if (firstBlockHeight != null) {
      if (totalBlockHeightDifference > 0) {
        fetchPhasePercentage = calculatePercentageBasedOnBlockHeights();
      } else {
        // If the difference is zero means that the first phase was concluded.
        print('The first phase just finished!');
        fetchPhasePercentage = 1;
      }
      final percentage =
          calculatePercentageBasedOnBlockHeights() * fetchPhaseWeight;
      yield percentage;
    }

    final isDeepSync = lastBlockHeight == 0;
    final isTrustedBlock =
        t.block != null && t.block!.height <= currentBlockHeight - 15;
    if (isDeepSync && isTrustedBlock) {
      // TODO: re-visit this - any way of avoiding the conditional?
      await gqlNodesCache.put(driveId, t);
    }
  }
  print('Done fetching data - ${gqlDriveHistory.driveId}');

  final fetchPhaseTotalTime =
      DateTime.now().difference(fetchPhaseStartDT).inMilliseconds;

  logSync(
    '''
      Duration of fetch phase for ${drive.name} : $fetchPhaseTotalTime ms \n
      Progress by block height: $fetchPhasePercentage% \n
      Starting parse phase \n
    ''',
  );

  try {
    yield* _parseDriveTransactionsIntoDatabaseEntities(
      ghostFolders: ghostFolders,
      driveDao: driveDao,
      arweave: arweave,
      database: database,
      transactions: transactions,
      drive: drive,
      driveKey: driveKey,
      currentBlockHeight: currentBlockHeight,
      lastBlockHeight: lastBlockHeight,
      batchSize: transactionParseBatchSize,
      snapshotDriveHistory: snapshotDriveHistory,
      ownerAddress: ownerAddress,
    ).map(
      (parseProgress) => parseProgress * 0.9,
    );
  } catch (e) {
    print('[Sync Drive] Error while parsing transactions: $e');
    rethrow;
  }

  await SnapshotItemOnChain.dispose(drive.id);

  final syncDriveTotalTime =
      DateTime.now().difference(startSyncDT).inMilliseconds;

  final averageBetweenFetchAndGet = fetchPhaseTotalTime / syncDriveTotalTime;

  logSync(
    '''
      Drive ${drive.name} completed parse phase\n
      Progress by block height: $fetchPhasePercentage% \n
      Starting parse phase \n
      Sync duration : $syncDriveTotalTime ms}.\n
      Parsing used ${(averageBetweenFetchAndGet * 100).toStringAsFixed(2)}% of drive sync process.\n
    ''',
  );
}
