part of 'package:ardrive/blocs/sync/sync_cubit.dart';

/// Computes the new drive revisions from the provided entities, inserts them into the database,
/// and returns the latest revision.
Future<DriveRevisionsCompanion?> _addNewDriveEntityRevisions({
  required DriveDao driveDao,
  required Database database,
  required Iterable<DriveEntity> newEntities,
}) async {
  DriveRevisionsCompanion? latestRevision;

  final newRevisions = <DriveRevisionsCompanion>[];
  for (final entity in newEntities) {
    latestRevision ??= await driveDao
        .latestDriveRevisionByDriveId(driveId: entity.id!)
        .getSingleOrNull()
        .then((r) => r?.toCompanion(true));

    final revisionPerformedAction =
        entity.getPerformedRevisionAction(latestRevision);
    if (revisionPerformedAction == null) {
      continue;
    }
    final revision =
        entity.toRevisionCompanion(performedAction: revisionPerformedAction);

    if (revision.action.value.isEmpty) {
      continue;
    }

    newRevisions.add(revision);
    latestRevision = revision;
  }

  await database.batch((b) {
    b.insertAllOnConflictUpdate(database.driveRevisions, newRevisions);
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
          .toList(),
    );
  });

  return latestRevision;
}

/// Computes the refreshed drive entries from the provided revisions and returns them as a map keyed by their ids.
Future<DrivesCompanion> _computeRefreshedDriveFromRevision({
  required DriveDao driveDao,
  required DriveRevisionsCompanion latestRevision,
}) async {
  final oldestRevision = await driveDao
      .oldestDriveRevisionByDriveId(driveId: latestRevision.driveId.value)
      .getSingleOrNull();

  return latestRevision.toEntryCompanion().copyWith(
        dateCreated: Value(
          oldestRevision?.dateCreated ?? latestRevision.dateCreated as DateTime,
        ),
      );
}
