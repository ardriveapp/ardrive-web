part of '../entities/arfs_entities.dart';

abstract class ARFSFactory {
  ARFSFileEntity getARFSFileFromFileWithLatestRevisionTransactions(
    FileWithLatestRevisionTransactions file,
  );
  ARFSFileEntity getARFSFileFromFileRevisionWithTransactions(
    FileRevisionWithTransactions file,
  );
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
    );
  }

  @override
  ARFSFileEntity getARFSFileFromFileRevisionWithTransactions(
      FileRevisionWithTransactions file) {
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
}
