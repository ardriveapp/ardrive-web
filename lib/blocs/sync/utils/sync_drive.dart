part of 'package:ardrive/blocs/sync/sync_cubit.dart';

Stream<SyncProgress> _syncDrive(
  String driveId, {
  required DriveDao driveDao,
  required ProfileState profileState,
  required ArweaveService arweaveService,
  required Database database,
  required SyncProgress syncProgress,
  required double totalProgress,
  required Function addError,
  required int currentBlockHeight,
  required int lastBlockHeight,
}) async* {
  /// Variables to count the current drive's progress information
  final drive = await driveDao.driveById(driveId: driveId).getSingle();

  final startSyncDT = DateTime.now();

  logSync('Starting Drive ${drive.name} sync.');

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

  logSync('Getting all information about the drive ${drive.name}\n');

  final transactions =
      <DriveEntityHistory$Query$TransactionConnection$TransactionEdge>[];

  final transactionsStream = arweaveService
      .getAllTransactionsFromDrive(driveId, lastBlockHeight: lastBlockHeight)
      .handleError((err) {
    addError(err);
  }).asBroadcastStream();

  /// The first block height from this drive.
  int? firstBlockHeight;

  /// In order to measure the sync progress by the block height, we use the difference
  /// between the first block and the `currentBlockHeight`
  late int totalBlockHeightDifference;

  /// This percentage is based on block heights.
  var fetchPhasePercentage = 0.0;

  /// First phase of the sync
  /// Here we get all transactions from its drive.
  await for (var t in transactionsStream) {
    if (t.isEmpty) continue;

    double calculatePercentageBasedOnBlockHeights() {
      final block = t.last.node.block;

      if (block != null) {
        return (1 -
            ((currentBlockHeight - block.height) / totalBlockHeightDifference));
      }
      logSync(
          'The transaction block is null.\nTransaction node id: ${t.first.node.id}');

      /// if the block is null, we don't calculate and keep the same percentage
      return fetchPhasePercentage;
    }

    /// Initialize only once `firstBlockHeight` and `totalBlockHeightDifference`
    if (firstBlockHeight == null) {
      final block = t.first.node.block;

      if (block != null) {
        firstBlockHeight = block.height;
        totalBlockHeightDifference = currentBlockHeight - firstBlockHeight;
      } else {
        logSync(
          'The transaction block is null.\nTransaction node id: ${t.first.node.id}',
        );
      }
    }

    transactions.addAll(t);

    /// We can only calculate the fetch percentage if we have the `firstBlockHeight`
    if (firstBlockHeight != null) {
      totalProgress += _calculateProgressInFetchPhasePercentage(
        syncProgress,
        _calculatePercentageProgress(
            fetchPhasePercentage, calculatePercentageBasedOnBlockHeights()),
      );

      syncProgress = syncProgress.copyWith(
          progress: totalProgress,
          entitiesNumber: syncProgress.entitiesNumber + t.length);

      yield syncProgress;

      if (totalBlockHeightDifference > 0) {
        fetchPhasePercentage += _calculatePercentageProgress(
            fetchPhasePercentage, calculatePercentageBasedOnBlockHeights());
      } else {
        // If the difference is zero means that the first phase was concluded.
        fetchPhasePercentage = 1;
      }
    }
  }

  final fetchPhaseTotalTime =
      DateTime.now().difference(fetchPhaseStartDT).inMilliseconds;

  logSync(
      'It took $fetchPhaseTotalTime milliseconds to get all ${drive.name}\'s transactions.\n');

  logSync('Percentage based on blocks: $fetchPhasePercentage\n');

  /// Fill the remaining percentage.
  /// It is needed because the phase one isn't accurate and possibly will not
  /// match 100% every time
  totalProgress += _calculateProgressInFetchPhasePercentage(
    syncProgress,
    (1 - fetchPhasePercentage),
  );

  logSync('Total progress after fetch phase: $totalProgress');

  syncProgress = syncProgress.copyWith(progress: totalProgress);

  yield syncProgress;

  logSync('Drive ${drive.name} is going to the 2nd phase\n');

  syncProgress = syncProgress.copyWith(
      numberOfDrivesAtGetMetadataPhase:
          syncProgress.numberOfDrivesAtGetMetadataPhase + 1);

  yield* _parseDriveTransactionsIntoDatabaseEntities(
    driveDao: driveDao,
    arweaveService: arweaveService,
    database: database,
    syncProgress: syncProgress,
    totalProgress: totalProgress,
    transactions: transactions,
    drive: drive,
    driveKey: driveKey,
    currentBlockHeight: currentBlockHeight,
    lastBlockHeight: lastBlockHeight,
  );

  logSync('Drive ${drive.name} ended the 2nd phase successfully\n');

  final syncDriveTotalTime =
      DateTime.now().difference(startSyncDT).inMilliseconds;

  logSync(
      'It took $syncDriveTotalTime in milliseconds to sync the ${drive.name}.\n');

  final averageBetweenFetchAndGet = fetchPhaseTotalTime / syncDriveTotalTime;

  logSync(
      'The fetch phase took: ${(averageBetweenFetchAndGet * 100).toStringAsFixed(2)}% of the entire drive process.\n');

  syncProgress = syncProgress.copyWith(
    numberOfDrivesAtGetMetadataPhase:
        syncProgress.numberOfDrivesAtGetMetadataPhase - 1,
  );
}
