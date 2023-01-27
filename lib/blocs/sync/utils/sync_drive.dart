part of 'package:ardrive/blocs/sync/sync_cubit.dart';

const fetchPhaseWeight = 0.1;
const parsePhaseWeight = 0.9;

Stream<double> _syncDrive(
  String driveId, {
  required DriveDao driveDao,
  required ProfileState profileState,
  required ArweaveService arweaveService,
  required Database database,
  required Function addError,
  required int currentBlockHeight,
  required int lastBlockHeight,
  required int transactionParseBatchSize,
  required Map<FolderID, GhostFolder> ghostFolders,
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

  final snapshotsStream = arweaveService.getAllSnapshotsOfDrive(
    driveId,
    lastBlockHeight,
  );
  final List<SnapshotItem> snapshotItems = await SnapshotItem.instantiateAll(
    snapshotsStream,
  ).toList();
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
  );

  print('Total range to query for: ${totalRangeToQueryFor.rangeSegments}');
  print(
      'Sub ranges in snapshots: ${snapshotDriveHistory.subRanges.rangeSegments}');
  print('Sub ranges in GQL: ${gqlDriveHistorySubRanges.rangeSegments}');

  final DriveHistoryComposite driveHistory = DriveHistoryComposite(
    subRanges: totalRangeToQueryFor,
    gqlDriveHistory: gqlDriveHistory,
    snapshotDriveHistory: snapshotDriveHistory,
  );

  final transactionsStream = driveHistory.getNextStream();

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

  yield* _parseDriveTransactionsIntoDatabaseEntities(
    ghostFolders: ghostFolders,
    driveDao: driveDao,
    arweaveService: arweaveService,
    database: database,
    transactions: transactions,
    drive: drive,
    driveKey: driveKey,
    currentBlockHeight: currentBlockHeight,
    lastBlockHeight: lastBlockHeight,
    batchSize: transactionParseBatchSize,
    snapshotDriveHistory: snapshotDriveHistory,
  ).map(
    (parseProgress) => parseProgress * 0.9,
  );

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
