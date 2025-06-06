import 'package:ardrive/entities/entities.dart';
import 'package:drift/drift.dart';

import 'models.dart';

extension DriveRevisionWithTransactionExtensions
    on DriveRevisionWithTransaction {
  String get confirmationStatus => metadataTx.status;
}

extension DriveRevisionCompanionExtensions on DriveRevisionsCompanion {
  /// Converts the revision to an instance of [DriveEntriesCompanion].
  ///
  /// This instance will not overwrite the encryption keys on private drives.
  DrivesCompanion toEntryCompanion() => DrivesCompanion.insert(
        id: driveId.value,
        rootFolderId: rootFolderId.value,
        ownerAddress: ownerAddress.value,
        name: name.value,
        lastUpdated: dateCreated,
        privacy: privacy.value,
        customGQLTags: customGQLTags,
        customJsonMetadata: customJsonMetadata,
        isHidden: isHidden,
      );

  /// Returns a [NetworkTransactionsCompanion] representing the metadata transaction
  /// of this entity.
  NetworkTransactionsCompanion getTransactionCompanion() =>
      NetworkTransactionsCompanion.insert(
          id: metadataTxId.value, dateCreated: dateCreated);
}

extension DriveEntityExtensions on DriveEntity {
  /// Converts the entity to an instance of [DriveRevisionsCompanion].
  ///
  /// This requires a `performedAction` to be specified.
  DriveRevisionsCompanion toRevisionCompanion(
          {required String performedAction}) =>
      DriveRevisionsCompanion.insert(
        driveId: id!,
        ownerAddress: ownerAddress,
        rootFolderId: rootFolderId!,
        name: name!,
        privacy: privacy!,
        metadataTxId: txId,
        dateCreated: Value(createdAt),
        action: performedAction,
        bundledIn: Value(bundledIn),
        customGQLTags: Value(customGqlTagsAsString),
        customJsonMetadata: Value(customJsonMetadataAsString),
        isHidden: Value(isHidden ?? false),
      );

  /// Returns the action performed on the Drive that lead to the new revision.
  String? getPerformedRevisionAction(
      [DriveRevisionsCompanion? previousRevision]) {
    if (previousRevision == null) {
      return RevisionAction.create;
    } else if (name != previousRevision.name.value) {
      return RevisionAction.rename;
    } else if (isHidden != null &&
        previousRevision.isHidden.value != isHidden) {
      return isHidden! ? RevisionAction.hide : RevisionAction.unhide;
    }

    return null;
  }
}
