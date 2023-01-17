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

// extension SnapshotEntityExtensions on SnapshotEntity {
//   /// Converts the entity to an instance of [FileRevisionsCompanion].
//   ///
//   /// This requires a `performedAction` to be specified.
//   FileRevisionsCompanion toRevisionCompanion({
//     required String performedAction,
//   }) =>
//       FileRevisionsCompanion.insert(
//         fileId: id!,
//         driveId: driveId!,
//         name: name!,
//         parentFolderId: parentFolderId!,
//         size: size!,
//         lastModifiedDate: lastModifiedDate ?? DateTime.now(),
//         metadataTxId: txId,
//         dataTxId: dataTxId!,
//         dateCreated: Value(createdAt),
//         dataContentType: Value(dataContentType),
//         action: performedAction,
//         bundledIn: Value(bundledIn),
//       );

//   FileRevision toRevision({
//     required String performedAction,
//   }) =>
//       FileRevision(
//         fileId: id!,
//         driveId: driveId!,
//         name: name!,
//         parentFolderId: parentFolderId!,
//         size: size!,
//         lastModifiedDate: lastModifiedDate ?? DateTime.now(),
//         metadataTxId: txId,
//         dataTxId: dataTxId!,
//         dateCreated: createdAt,
//         dataContentType: dataContentType,
//         action: performedAction,
//         bundledIn: bundledIn,
//       );

//   /// Returns the action performed on the file that lead to the new revision.
//   String? getPerformedRevisionAction(
//       [FileRevisionsCompanion? previousRevision]) {
//     if (previousRevision == null) {
//       return RevisionAction.create;
//     } else if (name != previousRevision.name.value) {
//       return RevisionAction.rename;
//     } else if (parentFolderId != previousRevision.parentFolderId.value) {
//       return RevisionAction.move;
//     } else if (dataTxId != previousRevision.dataTxId.value) {
//       return RevisionAction.uploadNewVersion;
//     }

//     return null;
//   }
// }
