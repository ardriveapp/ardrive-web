import 'package:ardrive/entities/entities.dart';
import 'package:drift/drift.dart';

import 'models.dart';

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
        path: rootPath,
        lastUpdated: dateCreated,
        lastModifiedDate: lastModifiedDate.value,
        dataContentType: dataContentType,
        bundledIn: bundledIn,
        customGQLTags: customGQLTags,
        customJsonMetadata: customJsonMetadata,
        pinnedDataOwnerAddress: pinnedDataOwnerAddress,
        isHidden: isHidden.value,
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
  FileRevisionsCompanion toRevisionCompanion({
    required String performedAction,
  }) =>
      FileRevisionsCompanion.insert(
        fileId: id!,
        driveId: driveId!,
        name: name!,
        parentFolderId: parentFolderId!,
        size: size!,
        lastModifiedDate: lastModifiedDate ?? DateTime.now(),
        metadataTxId: txId,
        dataTxId: dataTxId!,
        dateCreated: Value(createdAt),
        dataContentType: Value(dataContentType),
        action: performedAction,
        bundledIn: Value(bundledIn),
        customGQLTags: Value(customGqlTagsAsString),
        customJsonMetadata: Value(customJsonMetadataAsString),
        pinnedDataOwnerAddress: Value(pinnedDataOwnerAddress),
        isHidden: isHidden ?? false,
      );

  FileRevision toRevision({
    required String performedAction,
  }) =>
      FileRevision(
        fileId: id!,
        driveId: driveId!,
        name: name!,
        parentFolderId: parentFolderId!,
        size: size!,
        lastModifiedDate: lastModifiedDate ?? DateTime.now(),
        metadataTxId: txId,
        dataTxId: dataTxId!,
        dateCreated: createdAt,
        dataContentType: dataContentType,
        action: performedAction,
        bundledIn: bundledIn,
        customGQLTags: customGqlTagsAsString,
        customJsonMetadata: customJsonMetadataAsString,
        pinnedDataOwnerAddress: pinnedDataOwnerAddress,
        isHidden: isHidden ?? false,
      );

  /// Returns the action performed on the file that lead to the new revision.
  String? getPerformedRevisionAction(
      [FileRevisionsCompanion? previousRevision]) {
    if (previousRevision == null) {
      return RevisionAction.create;
    } else if (name != previousRevision.name.value) {
      return RevisionAction.rename;
    } else if (parentFolderId != previousRevision.parentFolderId.value) {
      return RevisionAction.move;
    } else if (dataTxId != previousRevision.dataTxId.value) {
      return RevisionAction.uploadNewVersion;
    } else if (isHidden == true && previousRevision.isHidden.value == false) {
      return RevisionAction.hide;
    } else if (isHidden == false && previousRevision.isHidden.value == true) {
      return RevisionAction.unhide;
    }

    return null;
  }
}
