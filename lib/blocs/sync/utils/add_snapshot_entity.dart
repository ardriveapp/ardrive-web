part of 'package:ardrive/blocs/sync/sync_cubit.dart';

/// Computes the new file revisions from the provided entities, inserts them into the database,
/// and returns only the latest revisions.
Future<List<SnapshotEntriesCompanion>> _addNewSnapshotEntities({
  required DriveDao driveDao,
  required Database database,
  required String driveId,
  required Iterable<SnapshotEntity> newEntities,
}) async {
  // The latest file revisions, keyed by their entity ids.
  // final latestRevisions = <String, SnapshotEntriesCompanion>{};

  print('Adding ${newEntities.length} new snapshot entities...');

  final newEntries = <SnapshotEntriesCompanion>[];
  for (final entity in newEntities) {
    // if (!latestRevisions.containsKey(entity.id)) {
    //   final revisions = await driveDao
    //       .latestFileRevisionByFileId(driveId: driveId, fileId: entity.id!)
    //       .getSingleOrNull();
    //   if (revisions != null) {
    //     latestRevisions[entity.id!] = revisions.toCompanion(true);
    //   }
    // }

    // final revisionPerformedAction =
    //     entity.getPerformedRevisionAction(latestRevisions[entity.id]);
    // if (revisionPerformedAction == null) {
    //   continue;
    // }
    // If Parent-Folder-Id is missing for a file, put it in the root folder

    // entity.parentFolderId = entity.parentFolderId ?? rootPath;

    print('Adding new snapshot entity: ${entity.id}');

    final revision = SnapshotEntriesCompanion.insert(
      id: entity.id!,
      txId: entity.txId,
      driveId: entity.driveId!,
      blockStart: entity.blockStart!,
      blockEnd: entity.blockEnd!,
      dataStart: entity.dataStart!,
      dataEnd: entity.dataEnd!,
      dateCreated: Value<DateTime>(entity.createdAt),
    );

    newEntries.add(revision);

    print('Added new snapshot entity: ${entity.id}');

    // if (revision.action.value.isEmpty) {
    //   continue;
    // }

    // newRevisions.add(revision);
    // latestRevisions[entity.id!] = revision;
  }

  await database.batch((b) {
    print(
      'Inserting ${newEntries.length} snapshot entries into the database...',
    );
    b.insertAllOnConflictUpdate(database.snapshotEntries, newEntries);
    b.insertAllOnConflictUpdate(
        database.networkTransactions,
        newEntries
            .expand(
              (rev) => [
                rev.getTransactionCompanion(),
              ],
            )
            .toList());
  });

  print('Inserted ${newEntries.length} snapshot entries into the database.');

  return newEntries;
}

// /// Computes the refreshed file entries from the provided revisions and returns them as a map keyed by their ids.
// Future<Map<String, FileEntriesCompanion>>
//     _computeRefreshedFileEntriesFromRevisions({
//   required DriveDao driveDao,
//   required String driveId,
//   required List<FileRevisionsCompanion> revisionsByFileId,
// }) async {
//   final updatedFilesById = {
//     for (final revision in revisionsByFileId)
//       revision.fileId.value: revision.toEntryCompanion(),
//   };

//   for (final fileId in updatedFilesById.keys) {
//     final oldestRevision = await driveDao
//         .oldestFileRevisionByFileId(driveId: driveId, fileId: fileId)
//         .getSingleOrNull();

//     updatedFilesById[fileId] = updatedFilesById[fileId]!.copyWith(
//         dateCreated: Value(oldestRevision?.dateCreated ??
//             updatedFilesById[fileId]!.dateCreated as DateTime));
//   }

//   return updatedFilesById;
// }
