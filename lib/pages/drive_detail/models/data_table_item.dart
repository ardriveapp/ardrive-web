import 'dart:convert';

import 'package:ardrive/arns/utils/parse_assigned_names_from_string.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/models/license.dart';
import 'package:ardrive/services/license/license_state.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';

abstract class ArDriveDataTableItem extends IndexedItem {
  final String name;
  final int? size;
  final DateTime lastUpdated;
  final DateTime dateCreated;
  final LicenseType? licenseType;
  final String contentType;
  final String? fileStatusFromTransactions;
  final String id;
  final String driveId;
  final bool isOwner;
  final bool isHidden;

  ArDriveDataTableItem({
    required this.id,
    this.size,
    required this.driveId,
    required this.name,
    required this.lastUpdated,
    required this.dateCreated,
    this.licenseType,
    required this.contentType,
    this.fileStatusFromTransactions,
    required int index,
    required this.isOwner,
    this.isHidden = false,
  }) : super(index);
}

class DriveDataItem extends ArDriveDataTableItem {
  DriveDataItem({
    required super.id,
    required super.driveId,
    required super.name,
    required super.lastUpdated,
    required super.dateCreated,
    super.contentType = 'drive',
    required super.index,
    required super.isOwner,
    super.isHidden,
  });

  @override
  List<Object?> get props => [id, name];
}

class FolderDataTableItem extends ArDriveDataTableItem {
  final String? parentFolderId;
  final bool isGhostFolder;

  FolderDataTableItem({
    required super.driveId,
    required String folderId,
    required super.name,
    required super.lastUpdated,
    required super.dateCreated,
    required super.contentType,
    super.fileStatusFromTransactions,
    super.isHidden,
    required super.index,
    required super.isOwner,
    this.parentFolderId,
    this.isGhostFolder = false,
  }) : super(id: folderId);

  @override
  List<Object> get props => [id, name, isHidden];
}

class FileDataTableItem extends ArDriveDataTableItem {
  final String fileId;
  final String parentFolderId;
  final String dataTxId;
  final String? licenseTxId;
  final String? bundledIn;
  final DateTime lastModifiedDate;
  final NetworkTransaction? metadataTx;
  final NetworkTransaction? dataTx;
  final String? pinnedDataOwnerAddress;
  final Thumbnail? thumbnail;
  final List<String>? assignedNames;
  final bool isManifest;

  FileDataTableItem(
      {required super.driveId,
      required super.lastUpdated,
      required super.name,
      required super.size,
      required super.dateCreated,
      required super.contentType,
      super.isHidden,
      super.fileStatusFromTransactions,
      required super.index,
      required super.isOwner,
      required this.fileId,
      required this.parentFolderId,
      required this.dataTxId,
      required this.lastModifiedDate,
      required this.metadataTx,
      required this.dataTx,
      required this.pinnedDataOwnerAddress,
      required this.isManifest,
      this.assignedNames,
      this.thumbnail,
      super.licenseType,
      this.licenseTxId,
      this.bundledIn})
      : super(id: fileId);

  @override
  List<Object> get props => [fileId, name, isHidden];
}

class DriveDataTableItemMapper {
  static FileDataTableItem toFileDataTableItem(
    FileWithLicenseAndLatestRevisionTransactions file,
    int index,
    bool isOwner,
  ) {
    return FileDataTableItem(
      isOwner: isOwner,
      lastModifiedDate: file.lastModifiedDate,
      name: file.name,
      size: file.size,
      lastUpdated: file.lastUpdated,
      dateCreated: file.dateCreated,
      contentType: file.dataContentType ?? '',
      fileStatusFromTransactions: fileStatusFromTransactions(
        file.metadataTx,
        file.dataTx,
      ).toString(),
      fileId: file.id,
      driveId: file.driveId,
      parentFolderId: file.parentFolderId,
      dataTxId: file.dataTxId,
      bundledIn: file.bundledIn,
      licenseTxId: file.licenseTxId,
      metadataTx: file.metadataTx,
      dataTx: file.dataTx,
      licenseType: file.license?.toCompanion(true).licenseTypeEnum,
      index: index,
      pinnedDataOwnerAddress: file.pinnedDataOwnerAddress,
      isHidden: file.isHidden,
      isManifest: FileTypeHelper.isManifest(file.dataContentType ?? ''),
      assignedNames: parseAssignedNamesFromString(file.assignedNames),
      thumbnail: file.thumbnail != null && file.thumbnail != 'null'
          ? Thumbnail.fromJson(jsonDecode(file.thumbnail!))
          : null,
    );
  }

  static FileDataTableItem fromFileEntryForSearchModal(
    FileEntry fileEntry,
  ) {
    return FileDataTableItem(
      isOwner: true,
      lastModifiedDate: fileEntry.lastModifiedDate,
      name: fileEntry.name,
      size: fileEntry.size,
      lastUpdated: fileEntry.lastUpdated,
      dateCreated: fileEntry.dateCreated,
      contentType: fileEntry.dataContentType ?? '',
      fileStatusFromTransactions: null,
      fileId: fileEntry.id,
      driveId: fileEntry.driveId,
      parentFolderId: fileEntry.parentFolderId,
      dataTxId: fileEntry.dataTxId,
      bundledIn: fileEntry.bundledIn,
      licenseTxId: fileEntry.licenseTxId,
      metadataTx: null,
      dataTx: null,
      index: 0,
      pinnedDataOwnerAddress: fileEntry.pinnedDataOwnerAddress,
      isHidden: fileEntry.isHidden,
      isManifest: FileTypeHelper.isManifest(fileEntry.dataContentType ?? ''),
      assignedNames: parseAssignedNamesFromString(fileEntry.assignedNames),
      thumbnail: fileEntry.thumbnail != null && fileEntry.thumbnail != 'null'
          ? Thumbnail.fromJson(jsonDecode(fileEntry.thumbnail!))
          : null,
    );
  }

  static FolderDataTableItem fromFolderEntry(
    FolderEntry folderEntry,
    int index,
    bool isOwner,
  ) {
    return FolderDataTableItem(
      isOwner: isOwner,
      isGhostFolder: folderEntry.isGhost,
      index: index,
      driveId: folderEntry.driveId,
      folderId: folderEntry.id,
      parentFolderId: folderEntry.parentFolderId,
      name: folderEntry.name,
      lastUpdated: folderEntry.lastUpdated,
      dateCreated: folderEntry.dateCreated,
      contentType: 'folder',
      fileStatusFromTransactions: null,
      isHidden: folderEntry.isHidden,
    );
  }

  static DriveDataItem fromDrive(
    Drive drive,
    Function(ArDriveDataTableItem) onPressed,
    int index,
    bool isOwner,
  ) {
    return DriveDataItem(
      isOwner: isOwner,
      index: index,
      driveId: drive.id,
      name: drive.name,
      lastUpdated: drive.lastUpdated,
      dateCreated: drive.dateCreated,
      contentType: 'drive',
      id: drive.id,
      isHidden: false, // TODO: update me when drives can be hidden
    );
  }

  static FileDataTableItem fromRevision(FileRevision revision, bool isOwner) {
    return FileDataTableItem(
      isOwner: isOwner,
      lastModifiedDate: revision.lastModifiedDate,
      name: revision.name,
      size: revision.size,
      lastUpdated: revision.lastModifiedDate,
      dateCreated: revision.dateCreated,
      contentType: revision.dataContentType ?? '',
      fileStatusFromTransactions: null,
      fileId: revision.fileId,
      driveId: revision.driveId,
      parentFolderId: revision.parentFolderId,
      dataTxId: revision.dataTxId,
      bundledIn: revision.bundledIn,
      licenseTxId: revision.licenseTxId,
      metadataTx: null,
      dataTx: null,
      index: 0,
      pinnedDataOwnerAddress: revision.pinnedDataOwnerAddress,
      isHidden: revision.isHidden,
      isManifest: FileTypeHelper.isManifest(revision.dataContentType ?? ''),
      assignedNames: parseAssignedNamesFromString(revision.assignedNames),
      thumbnail: revision.thumbnail != null && revision.thumbnail != 'null'
          ? Thumbnail.fromJson(jsonDecode(revision.thumbnail!))
          : null,
    );
  }
}
