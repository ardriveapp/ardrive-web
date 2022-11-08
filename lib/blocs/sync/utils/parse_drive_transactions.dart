part of 'package:ardrive/blocs/sync/sync_cubit.dart';

/// Sync Second Phase
///
/// Paginate the process in pages of `pageCount`
///
/// It is needed because of close connection issues when made a huge number of requests to get the metadata,
/// and also to accomplish a better visualization of the sync progress.
Stream<SyncProgress> _parseDriveTransactionsIntoDatabaseEntities({
  required DriveDao driveDao,
  required Database database,
  required ArweaveService arweaveService,
  required List<DriveEntityHistory$Query$TransactionConnection$TransactionEdge>
      transactions,
  required Drive drive,
  required SecretKey? driveKey,
  required int lastBlockHeight,
  required int currentBlockHeight,
  required SyncProgress syncProgress,
  required double totalProgress,
}) async* {
  final pageCount =
      200 ~/ (syncProgress.drivesCount - syncProgress.drivesSynced);
  var currentDriveEntitiesSynced = 0;
  var driveSyncProgress = 0.0;
  logSync(
      'number of drives at get metadata phase : ${syncProgress.numberOfDrivesAtGetMetadataPhase}');

  if (transactions.isEmpty) {
    await driveDao.writeToDrive(DrivesCompanion(
      id: Value(drive.id),
      lastBlockHeight: Value(currentBlockHeight),
      syncCursor: const Value(null),
    ));

    /// If there's nothing to sync, we assume that all were synced
    totalProgress += _calculateProgressInGetPhasePercentage(
      syncProgress,
      1,
    ); // 100%
    syncProgress = syncProgress.copyWith(progress: totalProgress);
    yield syncProgress;
    return;
  }
  final currentDriveEntitiesCounter = transactions.length;

  logSync(
      'The total number of entities of the drive ${drive.name} to be synced is: $currentDriveEntitiesCounter\n');

  final owner = await arweave.getOwnerForDriveEntityWithId(drive.id);

  double calculateDriveSyncPercentage() =>
      currentDriveEntitiesSynced / currentDriveEntitiesCounter;

  double calculateDrivePercentProgress() => _calculatePercentageProgress(
      driveSyncProgress, calculateDriveSyncPercentage());

  yield* _paginateProcess<
          DriveEntityHistory$Query$TransactionConnection$TransactionEdge>(
      list: transactions,
      pageCount: pageCount,
      itemsPerPageCallback: (items) async* {
        logSync('Getting metadata from drive ${drive.name}');

        final entityHistory =
            await arweave.createDriveEntityHistoryFromTransactions(
                items, driveKey, owner, lastBlockHeight);

        // Create entries for all the new revisions of file and folders in this drive.
        final newEntities = entityHistory.blockHistory
            .map((b) => b.entities)
            .expand((entities) => entities);

        currentDriveEntitiesSynced += items.length - newEntities.length;

        totalProgress += _calculateProgressInGetPhasePercentage(
          syncProgress,
          calculateDrivePercentProgress(),
        );

        syncProgress = syncProgress.copyWith(
            progress: totalProgress,
            entitiesSynced:
                syncProgress.entitiesSynced + currentDriveEntitiesSynced);

        yield syncProgress;

        driveSyncProgress += _calculatePercentageProgress(
            driveSyncProgress, calculateDriveSyncPercentage());

        // Handle the last page of newEntities, i.e; There's nothing more to sync
        if (newEntities.length < pageCount) {
          // Reset the sync cursor after every sync to pick up files from other instances of the app.
          // (Different tab, different window, mobile, desktop etc)
          await driveDao.writeToDrive(DrivesCompanion(
            id: Value(drive.id),
            lastBlockHeight: Value(currentBlockHeight),
            syncCursor: const Value(null),
          ));
        }

        await database.transaction(() async {
          final latestDriveRevision = await _addNewDriveEntityRevisions(
            driveDao: driveDao,
            database: database,
            newEntities: newEntities.whereType<DriveEntity>(),
          );
          final latestFolderRevisions = await _addNewFolderEntityRevisions(
            driveDao: driveDao,
            database: database,
            driveId: drive.id,
            newEntities: newEntities.whereType<FolderEntity>(),
          );
          final latestFileRevisions = await _addNewFileEntityRevisions(
            driveDao: driveDao,
            database: database,
            driveId: drive.id,
            newEntities: newEntities.whereType<FileEntity>(),
          );

          // Check and handle cases where there's no more revisions
          final updatedDrive = latestDriveRevision != null
              ? await _computeRefreshedDriveFromRevision(
                  driveDao: driveDao,
                  latestRevision: latestDriveRevision,
                )
              : null;

          final updatedFoldersById =
              await _computeRefreshedFolderEntriesFromRevisions(
            driveDao: driveDao,
            driveId: drive.id,
            revisionsByFolderId: latestFolderRevisions,
          );
          final updatedFilesById =
              await _computeRefreshedFileEntriesFromRevisions(
            driveDao: driveDao,
            driveId: drive.id,
            revisionsByFileId: latestFileRevisions,
          );

          currentDriveEntitiesSynced += newEntities.length;

          currentDriveEntitiesSynced -=
              updatedFoldersById.length + updatedFilesById.length;

          totalProgress += _calculateProgressInGetPhasePercentage(
            syncProgress,
            calculateDrivePercentProgress(),
          );

          syncProgress = syncProgress.copyWith(
            progress: totalProgress,
            entitiesSynced:
                syncProgress.entitiesSynced + currentDriveEntitiesSynced,
          );

          driveSyncProgress += _calculatePercentageProgress(
              driveSyncProgress, calculateDriveSyncPercentage());

          // Update the drive model, making sure to not overwrite the existing keys defined on the drive.
          if (updatedDrive != null) {
            await (database.update(database.drives)
                  ..whereSamePrimaryKey(updatedDrive))
                .write(updatedDrive);
          }

          // Update the folder and file entries before generating their new paths.
          await database.batch((b) {
            b.insertAllOnConflictUpdate(
                database.folderEntries, updatedFoldersById.values.toList());
            b.insertAllOnConflictUpdate(
                database.fileEntries, updatedFilesById.values.toList());
          });

          await _generateFsEntryPaths(
            driveDao: driveDao,
            driveId: drive.id,
            foldersByIdMap: updatedFoldersById,
            filesByIdMap: updatedFilesById,
          );

          currentDriveEntitiesSynced +=
              updatedFoldersById.length + updatedFilesById.length;

          totalProgress += _calculateProgressInGetPhasePercentage(
            syncProgress,
            calculateDrivePercentProgress(),
          );

          syncProgress = syncProgress.copyWith(
            progress: totalProgress,
            entitiesSynced:
                syncProgress.entitiesSynced + currentDriveEntitiesSynced,
          );

          driveSyncProgress += _calculatePercentageProgress(
              driveSyncProgress, calculateDriveSyncPercentage());
        });

        yield syncProgress;
      });

  logSync('''
        ${'- - ' * 10}
        Drive: ${drive.name} sync finishes.\n
        The progress was:                     ${driveSyncProgress * 100}
        Total progress until now:             ${(totalProgress * 100).roundToDouble()}
        The number of entities to be synced:  $currentDriveEntitiesCounter
        The Total number of synced entities:  $currentDriveEntitiesSynced
        ''');
}

Stream<SyncProgress> _paginateProcess<T>({
  required List<T> list,
  required Stream<SyncProgress> Function(List<T> items) itemsPerPageCallback,
  required int pageCount,
}) async* {
  if (list.isEmpty) {
    return;
  }

  final length = list.length;

  for (var i = 0; i < length / pageCount; i++) {
    final currentPage = <T>[];

    /// Mounts the list to be iterated
    for (var j = i * pageCount; j < ((i + 1) * pageCount); j++) {
      if (j >= length) {
        break;
      }

      currentPage.add(list[j]);
    }

    yield* itemsPerPageCallback(currentPage);
  }
}
