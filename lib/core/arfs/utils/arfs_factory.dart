part of '../entities/arfs_entities.dart';

abstract class ARFSFactory {
  ARFSFileEntity getARFSFileFromFileWithLatestRevisionTransactions(
    FileWithLatestRevisionTransactions file,
  );
  ARFSFileEntity getARFSFileFromFileRevisionWithLicenseAndTransactions(
    FileRevisionWithLicenseAndTransactions file,
  );
  ARFSFileEntity getARFSFileFromFileRevision(FileRevision file);
  ARFSFileEntity getARFSFileFromFileDataItemTable(FileDataTableItem file);

  ARFSDriveEntity getARFSDriveFromDriveDAOEntity(Drive drive);
  factory ARFSFactory() => _ARFSFactory();
}

class _ARFSFactory implements ARFSFactory {
  @override
  ARFSFileEntity getARFSFileFromFileWithLatestRevisionTransactions(
    FileWithLatestRevisionTransactions file,
  ) {
    return _ARFSFileEntity(
      appName: '',
      appVersion: '',
      arFS: '',
      contentType: file.dataContentType,
      driveId: file.driveId,
      entityType: EntityType.file,
      name: file.name,
      txId: file.dataTxId,
      unixTime: file.dateCreated,
      lastModifiedDate: file.lastModifiedDate,
      parentFolderId: file.parentFolderId,
      size: file.size,
      id: file.id,
      dataTxId: file.dataTxId,
      licenseTxId: file.licenseTxId,
      pinnedDataOwnerAddress: file.pinnedDataOwnerAddress,
      originalOwner: file.originalOwner,
      importSource: file.importSource,
    );
  }

  @override
  ARFSFileEntity getARFSFileFromFileRevisionWithLicenseAndTransactions(
      FileRevisionWithLicenseAndTransactions file) {
    return _ARFSFileEntity(
      appName: '',
      appVersion: '',
      arFS: '',
      contentType: file.dataContentType,
      driveId: file.driveId,
      entityType: EntityType.file,
      name: file.name,
      txId: file.dataTxId,
      unixTime: file.dateCreated,
      lastModifiedDate: file.lastModifiedDate,
      parentFolderId: file.parentFolderId,
      size: file.size,
      id: file.fileId,
      licenseTxId: file.licenseTxId,
      pinnedDataOwnerAddress: file.pinnedDataOwnerAddress,
      assignedNames: parseAssignedNamesFromString(file.assignedNames),
      originalOwner: file.originalOwner,
      importSource: file.importSource,
    );
  }

  @override
  ARFSDriveEntity getARFSDriveFromDriveDAOEntity(Drive drive) {
    return _ARFSDriveEntity(
      appName: '',
      appVersion: '',
      arFS: '',
      driveId: drive.id,
      entityType: EntityType.drive,
      name: drive.name,
      txId: '',
      unixTime: drive.dateCreated,
      drivePrivacy: drive.privacy == DrivePrivacy.private.name
          ? DrivePrivacy.private
          : DrivePrivacy.public,
      rootFolderId: drive.rootFolderId,
    );
  }

  @override
  ARFSFileEntity getARFSFileFromFileDataItemTable(FileDataTableItem file) {
    return _ARFSFileEntity(
      appName: '',
      appVersion: '',
      arFS: '',
      contentType: file.contentType,
      driveId: file.driveId,
      entityType: EntityType.file,
      name: file.name,
      txId: file.dataTxId,
      unixTime: file.dateCreated,
      lastModifiedDate: file.lastModifiedDate,
      parentFolderId: file.parentFolderId,
      size: file.size ?? 0,
      id: file.id,
      licenseTxId: file.licenseTxId,
      pinnedDataOwnerAddress: file.pinnedDataOwnerAddress,
      originalOwner: file.originalOwner,
      importSource: file.importSource,
    );
  }

  @override
  ARFSFileEntity getARFSFileFromFileRevision(FileRevision fileRevision) {
    return _ARFSFileEntity(
      appName: '',
      appVersion: '',
      arFS: '',
      driveId: fileRevision.driveId,
      entityType: EntityType.file,
      name: fileRevision.name,
      txId: fileRevision.metadataTxId,
      unixTime: fileRevision.dateCreated,
      id: fileRevision.fileId,
      size: fileRevision.size,
      lastModifiedDate: fileRevision.lastModifiedDate,
      parentFolderId: fileRevision.parentFolderId,
      contentType: fileRevision.dataContentType,
      dataTxId: fileRevision.dataTxId,
      pinnedDataOwnerAddress: fileRevision.pinnedDataOwnerAddress,
      assignedNames: parseAssignedNamesFromString(fileRevision.assignedNames),
      originalOwner: fileRevision.originalOwner,
      importSource: fileRevision.importSource,
    );
  }
}
