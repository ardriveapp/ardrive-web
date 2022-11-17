part of 'package:ardrive/blocs/sync/sync_cubit.dart';

/// Computes the new file revisions from the provided entities, inserts them into the database,
/// and returns only the latest revisions.
Future<List<FileRevisionsCompanion>> _addNewFileEntityRevisions({
  required DriveDao driveDao,
  required Database database,
  required String driveId,
  required Iterable<FileEntity> newEntities,
}) async {
  // The latest file revisions, keyed by their entity ids.
  final latestRevisions = <String, FileRevisionsCompanion>{};

  final newRevisions = <FileRevisionsCompanion>[];
  for (final entity in newEntities) {
    if (!latestRevisions.containsKey(entity.id) &&
        entity.parentFolderId != null) {
      final revisions = await driveDao
          .latestFileRevisionByFileId(driveId: driveId, fileId: entity.id!)
          .getSingleOrNull();
      if (revisions != null) {
        latestRevisions[entity.id!] = revisions.toCompanion(true);
      }
    }

    final revisionPerformedAction =
        entity.getPerformedRevisionAction(latestRevisions[entity.id]);
    if (revisionPerformedAction == null) {
      continue;
    }
    // If Parent-Folder-Id is missing for a file, put it in the root folder

    entity.parentFolderId = entity.parentFolderId ?? rootPath;
    final revision =
        entity.toRevisionCompanion(performedAction: revisionPerformedAction);

    if (revision.action.value.isEmpty) {
      continue;
    }

    newRevisions.add(revision);
    latestRevisions[entity.id!] = revision;
  }

  await database.batch((b) {
    b.insertAllOnConflictUpdate(database.fileRevisions, newRevisions);
    b.insertAllOnConflictUpdate(
        database.networkTransactions,
        newRevisions
            .expand(
              (rev) => [
                NetworkTransactionsCompanion.insert(
                  transactionDateCreated: rev.dateCreated,
                  id: rev.metadataTxId.value,
                  status: const Value(TransactionStatus.confirmed),
                ),
                // We cannot be sure that the data tx of files have been mined
                // so we'll mark it as pending initially.
                NetworkTransactionsCompanion.insert(
                  transactionDateCreated: rev.dateCreated,
                  id: rev.dataTxId.value,
                  status: const Value(TransactionStatus.pending),
                ),
              ],
            )
            .toList());
  });

  return latestRevisions.values.toList();
}

/// Computes the refreshed file entries from the provided revisions and returns them as a map keyed by their ids.
Future<Map<String, FileEntriesCompanion>>
    _computeRefreshedFileEntriesFromRevisions({
  required DriveDao driveDao,
  required String driveId,
  required List<FileRevisionsCompanion> revisionsByFileId,
}) async {
  final updatedFilesById = {
    for (final revision in revisionsByFileId)
      revision.fileId.value: revision.toEntryCompanion(),
  };

  for (final fileId in updatedFilesById.keys) {
    final oldestRevision = await driveDao
        .oldestFileRevisionByFileId(driveId: driveId, fileId: fileId)
        .getSingleOrNull();

    updatedFilesById[fileId] = updatedFilesById[fileId]!.copyWith(
        dateCreated: Value(oldestRevision?.dateCreated ??
            updatedFilesById[fileId]!.dateCreated as DateTime));
  }

  return updatedFilesById;
}
