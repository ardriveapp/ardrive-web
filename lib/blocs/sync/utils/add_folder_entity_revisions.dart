part of 'package:ardrive/blocs/sync/sync_cubit.dart';

/// Computes the new folder revisions from the provided entities, inserts them into the database,
/// and returns only the latest revisions.
Future<List<FolderRevisionsCompanion>> _addNewFolderEntityRevisions({
  required DriveDao driveDao,
  required Database database,
  required String driveId,
  required Iterable<FolderEntity> newEntities,
}) async {
  // The latest folder revisions, keyed by their entity ids.
  final latestRevisions = <String, FolderRevisionsCompanion>{};

  final newRevisions = <FolderRevisionsCompanion>[];
  for (final entity in newEntities) {
    if (!latestRevisions.containsKey(entity.id)) {
      final revisions = (await driveDao
          .latestFolderRevisionByFolderId(
              driveId: driveId, folderId: entity.id!)
          .getSingleOrNull());
      if (revisions != null) {
        latestRevisions[entity.id!] = revisions.toCompanion(true);
      }
    }

    final revisionPerformedAction =
        entity.getPerformedRevisionAction(latestRevisions[entity.id]);
    if (revisionPerformedAction == null) {
      continue;
    }
    final revision =
        entity.toRevisionCompanion(performedAction: revisionPerformedAction);

    if (revision.action.value.isEmpty) {
      continue;
    }

    newRevisions.add(revision);
    latestRevisions[entity.id!] = revision;
  }

  await database.batch((b) {
    b.insertAllOnConflictUpdate(database.folderRevisions, newRevisions);
    b.insertAllOnConflictUpdate(
        database.networkTransactions,
        newRevisions
            .map(
              (rev) => NetworkTransactionsCompanion.insert(
                transactionDateCreated: rev.dateCreated,
                id: rev.metadataTxId.value,
                status: const Value(TransactionStatus.confirmed),
              ),
            )
            .toList());
  });

  return latestRevisions.values.toList();
}

/// Computes the refreshed folder entries from the provided revisions and returns them as a map keyed by their ids.
Future<Map<String, FolderEntriesCompanion>>
    _computeRefreshedFolderEntriesFromRevisions({
  required DriveDao driveDao,
  required String driveId,
  required List<FolderRevisionsCompanion> revisionsByFolderId,
}) async {
  final updatedFoldersById = {
    for (final revision in revisionsByFolderId)
      revision.folderId.value: revision.toEntryCompanion(),
  };

  for (final folderId in updatedFoldersById.keys) {
    final oldestRevision = await driveDao
        .oldestFolderRevisionByFolderId(driveId: driveId, folderId: folderId)
        .getSingleOrNull();

    updatedFoldersById[folderId] = updatedFoldersById[folderId]!.copyWith(
        dateCreated: Value(oldestRevision?.dateCreated ??
            updatedFoldersById[folderId]!.dateCreated as DateTime));
  }

  return updatedFoldersById;
}
