import 'package:ardrive/entities/entities.dart';
import 'package:moor/moor.dart';

import 'models.dart';

extension FileRevisionWithTransactionsExtensions
    on FileRevisionWithTransactions {
  String get confirmationStatus {
    if (metadataTx.status == TransactionStatus.failed ||
        dataTx.status == TransactionStatus.failed) {
      return TransactionStatus.failed;
    } else if (metadataTx.status == TransactionStatus.pending ||
        dataTx.status == TransactionStatus.pending) {
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

  /// Returns a list of [NetworkTransactionsCompanion] representing the metadata and data transactions
  /// of this entity.
  List<NetworkTransactionsCompanion> getTransactionCompanions() => [
        NetworkTransactionsCompanion.insert(
            id: metadataTxId.value, dateCreated: dateCreated),
        NetworkTransactionsCompanion.insert(
            id: dataTxId.value, dateCreated: dateCreated),
      ];
}

extension FileEntityExtensions on FileEntity {
  /// Converts the entity to an instance of [FileRevisionsCompanion].
  ///
  /// This requires a `performedAction` to be specified.
  FileRevisionsCompanion toRevisionCompanion(
          {@required String performedAction}) =>
      FileRevisionsCompanion.insert(
        fileId: id,
        driveId: driveId,
        name: name,
        parentFolderId: parentFolderId,
        size: size,
        lastModifiedDate: lastModifiedDate,
        metadataTxId: txId,
        dataTxId: dataTxId,
        dateCreated: Value(createdAt),
        action: performedAction,
      );

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
