import 'package:ardrive/entities/entities.dart';

import 'models.dart';

extension FileRevisionExtensions on FileRevision {
  String get confirmationStatus {
    if (metadataTxStatus == TransactionStatus.failed ||
        dataTxStatus == TransactionStatus.failed) {
      return TransactionStatus.failed;
    } else if (metadataTxStatus == TransactionStatus.pending ||
        dataTxStatus == TransactionStatus.pending) {
      return TransactionStatus.pending;
    } else {
      return TransactionStatus.confirmed;
    }
  }
}

extension FileRevisionsCompanionExtensions on FileRevisionsCompanion {
  /// Converts the revision to an instance of [FileEntriesCompanion].
  ///
  /// This instance will lack a proper path and `dateCreated`.
  FileEntriesCompanion toEntryCompanion() => FileEntriesCompanion.insert(
        id: fileId.value,
        driveId: driveId.value,
        parentFolderId: parentFolderId.value,
        name: name.value,
        dataTxId: dataTxId.value,
        size: size.value,
        path: '',
        lastUpdated: dateCreated,
        lastModifiedDate: lastModifiedDate.value,
      );
}

extension FileEntityExtensions on FileEntity {
  /// Returns the action performed on the file that lead to the new revision.
  String getPerformedRevisionAction([FileRevisionsCompanion previousRevision]) {
    if (previousRevision == null) {
      return RevisionAction.create;
    } else if (name != previousRevision.name.value) {
      return RevisionAction.rename;
    } else if (parentFolderId != previousRevision.parentFolderId.value) {
      return RevisionAction.move;
    } else if (dataTxId != previousRevision.dataTxId.value) {
      return RevisionAction.uploadNewVersion;
    }

    return null;
  }
}
