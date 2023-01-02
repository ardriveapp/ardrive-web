part of 'package:ardrive/blocs/sync/sync_cubit.dart';

/// Process the transactions from the first phase into database entities.
/// This is done in batches to improve performance and provide more granular progress
Stream<double> _parseDriveTransactionsIntoDatabaseEntities({
  required DriveDao driveDao,
  required Database database,
  required ArweaveService arweave,
  required List<DriveEntityHistory$Query$TransactionConnection$TransactionEdge>
      transactions,
  required Drive drive,
  required SecretKey? driveKey,
  required int lastBlockHeight,
  required int currentBlockHeight,
  required int batchSize,
}) async* {
  final numberOfDriveEntitiesToParse = transactions.length;
  var numberOfDriveEntitiesParsed = 0;

  double driveEntityParseProgress() =>
      numberOfDriveEntitiesParsed / numberOfDriveEntitiesToParse;

  if (transactions.isEmpty) {
    await driveDao.writeToDrive(
      DrivesCompanion(
        id: Value(drive.id),
        lastBlockHeight: Value(currentBlockHeight),
        syncCursor: const Value(null),
      ),
    );

    /// If there's nothing to sync, we assume that all were synced

    yield 1;
    return;
  }

  logSync(
    'no. of entities in drive - ${drive.name} to be parsed are: $numberOfDriveEntitiesToParse\n',
  );

  final owner = await arweave.getOwnerForDriveEntityWithId(drive.id);

  yield* _batchProcess<
          DriveEntityHistory$Query$TransactionConnection$TransactionEdge>(
      list: transactions,
      batchSize: batchSize,
      endOfBatchCallback: (items) async* {
        logSync('Getting metadata from drive ${drive.name}');

        final entityHistory =
            await arweave.createDriveEntityHistoryFromTransactions(
                items, driveKey, owner, lastBlockHeight);

        // Create entries for all the new revisions of file and folders in this drive.
        final newEntities = entityHistory.blockHistory
            .map((b) => b.entities)
            .expand((entities) => entities);

        numberOfDriveEntitiesParsed += items.length - newEntities.length;

        yield driveEntityParseProgress();

        // Handle the last page of newEntities, i.e; There's nothing more to sync
        if (newEntities.length < batchSize) {
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

          numberOfDriveEntitiesParsed += newEntities.length;

          numberOfDriveEntitiesParsed -=
              updatedFoldersById.length + updatedFilesById.length;

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

          numberOfDriveEntitiesParsed +=
              updatedFoldersById.length + updatedFilesById.length;
        });
        yield driveEntityParseProgress();
      });

  logSync('''
        ${'- - ' * 10}
        drive: ${drive.name} sync completed.\n
        no. of transactions to be parsed into entities:  $numberOfDriveEntitiesToParse
        no. of parsed entities:  $numberOfDriveEntitiesParsed
        ''');
}

Stream<double> _batchProcess<T>({
  required List<T> list,
  required Stream<double> Function(List<T> items) endOfBatchCallback,
  required int batchSize,
}) async* {
  if (list.isEmpty) {
    return;
  }

  final length = list.length;

  for (var i = 0; i < length / batchSize; i++) {
    final currentBatch = <T>[];

    /// Mounts the list to be iterated
    for (var j = i * batchSize; j < ((i + 1) * batchSize); j++) {
      if (j >= length) {
        break;
      }

      currentBatch.add(list[j]);
    }

    yield* endOfBatchCallback(currentBatch);
  }
}
