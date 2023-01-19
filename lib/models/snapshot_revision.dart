import 'models.dart';

extension SnapshotEntriesCompanionExtensions on SnapshotEntriesCompanion {
  /// Converts the revision to an instance of [SnapshotEntriesCompanion].
  ///
  /// This instance will lack a proper path and `dateCreated`.
  SnapshotEntriesCompanion toEntryCompanion() =>
      SnapshotEntriesCompanion.insert(
        id: id.value,
        txId: txId.value,
        driveId: driveId.value,
        blockStart: blockStart.value,
        blockEnd: blockEnd.value,
        dateCreated: dateCreated,
        dataStart: dataStart.value,
        dataEnd: dataEnd.value,
      );

  /// Returns a list of [NetworkTransactionsCompanion] representing this entity.
  NetworkTransactionsCompanion getTransactionCompanions() =>
      NetworkTransactionsCompanion.insert(
        id: txId.value,
        dateCreated: dateCreated,
      );
}
