import 'package:ardrive/entities/entities.dart';

import 'models.dart';

extension FolderRevisionWithTransactionExtensions
    on FolderRevisionWithTransaction {
  String get confirmationStatus => metadataTx.status;
}

extension FolderRevisionCompanionExtensions on FolderRevisionsCompanion {
  /// Converts the revision to an instance of [FolderEntriesCompanion].
  ///
  /// This instance will lack a proper path and `dateCreated`.
  FolderEntriesCompanion toEntryCompanion() => FolderEntriesCompanion.insert(
        id: folderId.value,
        driveId: driveId.value,
        parentFolderId: parentFolderId,
        name: name.value,
        path: '',
        lastUpdated: dateCreated,
      );
}

extension FolderEntityExtensions on FolderEntity {
  /// Returns the action performed on the folder that lead to the new revision.
  String getPerformedRevisionAction(
      [FolderRevisionsCompanion previousRevision]) {
    if (previousRevision == null) {
      return RevisionAction.create;
    } else if (name != previousRevision.name.value) {
      return RevisionAction.rename;
    } else if (parentFolderId != previousRevision.parentFolderId.value) {
      return RevisionAction.move;
    }

    return null;
  }
}
