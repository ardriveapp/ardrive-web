import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';

/// Base class that represents common properties between [FileRevision] and [FileRevisionWithLicenseAndTransactions]
abstract class FileRevisionBase {
  final String fileId;
  final String driveId;
  final String name;
  final String parentFolderId;
  final int size;
  final DateTime lastModifiedDate;
  final String? dataContentType;
  final String metadataTxId;
  final String dataTxId;
  final String? licenseTxId;
  final String? thumbnail;
  final String? bundledIn;
  final DateTime dateCreated;
  final String? customJsonMetadata;
  final String? customGQLTags;
  final String action;
  final String? pinnedDataOwnerAddress;
  final bool isHidden;
  final String? assignedNames;
  final String? fallbackTxId;

  const FileRevisionBase({
    required this.fileId,
    required this.driveId,
    required this.name,
    required this.parentFolderId,
    required this.size,
    required this.lastModifiedDate,
    this.dataContentType,
    required this.metadataTxId,
    required this.dataTxId,
    this.licenseTxId,
    this.thumbnail,
    this.bundledIn,
    required this.dateCreated,
    this.customJsonMetadata,
    this.customGQLTags,
    required this.action,
    this.pinnedDataOwnerAddress,
    required this.isHidden,
    this.assignedNames,
    this.fallbackTxId,
  });

  /// Creates a [FileRevisionBase] from a [FileRevision]
  static FileRevisionBase fromFileRevision(FileRevision revision) {
    return _SimpleFileRevision(
      fileId: revision.fileId,
      driveId: revision.driveId,
      name: revision.name,
      parentFolderId: revision.parentFolderId,
      size: revision.size,
      lastModifiedDate: revision.lastModifiedDate,
      dataContentType: revision.dataContentType,
      metadataTxId: revision.metadataTxId,
      dataTxId: revision.dataTxId,
      licenseTxId: revision.licenseTxId,
      thumbnail: revision.thumbnail,
      bundledIn: revision.bundledIn,
      dateCreated: revision.dateCreated,
      customJsonMetadata: revision.customJsonMetadata,
      customGQLTags: revision.customGQLTags,
      action: revision.action,
      pinnedDataOwnerAddress: revision.pinnedDataOwnerAddress,
      isHidden: revision.isHidden,
      assignedNames: revision.assignedNames,
      fallbackTxId: revision.fallbackTxId,
    );
  }

  /// Creates a [FileRevisionBase] from a [FileRevisionWithLicenseAndTransactions]
  static FileRevisionBase fromFileRevisionWithLicense(
      FileRevisionWithLicenseAndTransactions revision) {
    return _SimpleFileRevision(
      fileId: revision.fileId,
      driveId: revision.driveId,
      name: revision.name,
      parentFolderId: revision.parentFolderId,
      size: revision.size,
      lastModifiedDate: revision.lastModifiedDate,
      dataContentType: revision.dataContentType,
      metadataTxId: revision.metadataTxId,
      dataTxId: revision.dataTxId,
      licenseTxId: revision.licenseTxId,
      thumbnail: revision.thumbnail,
      bundledIn: revision.bundledIn,
      dateCreated: revision.dateCreated,
      customJsonMetadata: revision.customJsonMetadata,
      customGQLTags: revision.customGQLTags,
      action: revision.action,
      pinnedDataOwnerAddress: revision.pinnedDataOwnerAddress,
      isHidden: revision.isHidden,
      assignedNames: revision.assignedNames,
      fallbackTxId: revision.fallbackTxId,
    );
  }
}

class _SimpleFileRevision extends FileRevisionBase {
  const _SimpleFileRevision({
    required super.fileId,
    required super.driveId,
    required super.name,
    required super.parentFolderId,
    required super.size,
    required super.lastModifiedDate,
    super.dataContentType,
    required super.metadataTxId,
    required super.dataTxId,
    super.licenseTxId,
    super.thumbnail,
    super.bundledIn,
    required super.dateCreated,
    super.customJsonMetadata,
    super.customGQLTags,
    required super.action,
    super.pinnedDataOwnerAddress,
    required super.isHidden,
    super.assignedNames,
    super.fallbackTxId,
  });
}
