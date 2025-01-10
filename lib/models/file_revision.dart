import 'dart:convert';

import 'package:ardrive/arns/utils/parse_assigned_names_from_string.dart';
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
        licenseTxId: Value(licenseTxId.value),
        size: size.value,
        lastUpdated: dateCreated,
        lastModifiedDate: lastModifiedDate.value,
        dataContentType: dataContentType,
        bundledIn: bundledIn,
        customGQLTags: customGQLTags,
        customJsonMetadata: customJsonMetadata,
        pinnedDataOwnerAddress: pinnedDataOwnerAddress,
        isHidden: isHidden,
        // TODO: path is not used in the app, so it's not necessary to set it
        path: '',
        thumbnail: Value(thumbnail.value),
        assignedNames: Value(assignedNames.value),
        fallbackTxId: fallbackTxId,
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
  }) {
    String? thumbnailData;
    String? assignedNamesData;
    if (thumbnail != null) {
      thumbnailData = jsonEncode(thumbnail?.toJson());
    }

    if (assignedNames != null) {
      assignedNamesData = jsonEncode({
        'assignedNames': assignedNames,
      });
    }

    return FileRevisionsCompanion.insert(
      fileId: id!,
      driveId: driveId!,
      name: name!,
      parentFolderId: parentFolderId!,
      size: size!,
      lastModifiedDate: lastModifiedDate ?? DateTime.now(),
      metadataTxId: txId,
      dataTxId: dataTxId!,
      licenseTxId: Value(licenseTxId),
      dateCreated: Value(createdAt),
      dataContentType: Value(dataContentType),
      action: performedAction,
      bundledIn: Value(bundledIn),
      customGQLTags: Value(customGqlTagsAsString),
      customJsonMetadata: Value(customJsonMetadataAsString),
      pinnedDataOwnerAddress: Value(pinnedDataOwnerAddress),
      isHidden: Value(isHidden ?? false),
      thumbnail: Value(thumbnailData),
      assignedNames: Value(assignedNamesData),
      fallbackTxId: Value(fallbackTxId),
    );
  }

  FileRevision toRevision({
    required String performedAction,
  }) {
    String? thumbnailData;
    String? assignedNamesData;
    if (thumbnail != null) {
      thumbnailData = jsonEncode(thumbnail?.toJson());
    }

    if (assignedNames != null) {
      assignedNamesData = jsonEncode({
        'assignedNames': assignedNames,
      });
    }

    return FileRevision(
      fileId: id!,
      driveId: driveId!,
      name: name!,
      parentFolderId: parentFolderId!,
      size: size!,
      lastModifiedDate: lastModifiedDate ?? DateTime.now(),
      metadataTxId: txId,
      dataTxId: dataTxId!,
      licenseTxId: licenseTxId,
      dateCreated: createdAt,
      dataContentType: dataContentType,
      action: performedAction,
      bundledIn: bundledIn,
      customGQLTags: customGqlTagsAsString,
      customJsonMetadata: customJsonMetadataAsString,
      pinnedDataOwnerAddress: pinnedDataOwnerAddress,
      isHidden: isHidden ?? false,
      thumbnail: thumbnailData,
      assignedNames: assignedNamesData,
    );
  }

  /// Returns the action performed on the file that lead to the new revision.
  String? getPerformedRevisionAction(
      [FileRevisionsCompanion? previousRevision]) {
    if (previousRevision == null) {
      return RevisionAction.create;
    } else if (fallbackTxId != null &&
        fallbackTxId != previousRevision.fallbackTxId.value) {
      return RevisionAction.uploadNewVersion;
    } else if (name != previousRevision.name.value) {
      return RevisionAction.rename;
    } else if (parentFolderId != previousRevision.parentFolderId.value) {
      return RevisionAction.move;
    } else if (dataTxId != previousRevision.dataTxId.value) {
      return RevisionAction.uploadNewVersion;
    } else if (licenseTxId != previousRevision.licenseTxId.value) {
      return RevisionAction.assertLicense;
    } else if (isHidden == true && previousRevision.isHidden.value == false) {
      return RevisionAction.hide;
    } else if (isHidden == false && previousRevision.isHidden.value == true) {
      return RevisionAction.unhide;
    } else if (thumbnail != null &&
        jsonEncode(thumbnail?.toJson()) != previousRevision.thumbnail.value) {
      return RevisionAction.createThumbnail;
    } else if (assignedNames != null) {
      final previousAssignedNames =
          parseAssignedNamesFromString(previousRevision.assignedNames.value);
      if (previousAssignedNames == null) {
        return RevisionAction.assignName;
      }
      if (assignedNames!.length > previousAssignedNames.length) {
        return RevisionAction.assignName;
      }
    }

    return null;
  }
}
