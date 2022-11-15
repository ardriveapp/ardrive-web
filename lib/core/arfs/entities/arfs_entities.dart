import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';

part '../utils/arfs_factory.dart';

abstract class ARFSEntity {
  ARFSEntity({
    required this.appName,
    required this.appVersion,
    required this.arFS,
    required this.driveId,
    required this.entityType,
    required this.name,
    required this.txId,
    required this.unixTime,
  });

  final String appName;
  final String appVersion;
  final String arFS;
  final String driveId;
  final EntityType entityType;
  final String name;
  final String txId;
  final DateTime unixTime;
}

abstract class PrivateARFSEntity implements ARFSEntity {
  PrivateARFSEntity({
    required this.cipher,
    required this.cipherIX,
    required this.driveKey,
  });

  final Cipher cipher;
  final String cipherIX;
  final String driveKey;
}

abstract class ARFSDriveEntity extends ARFSEntity {
  ARFSDriveEntity({
    required super.appName,
    required super.appVersion,
    required super.arFS,
    required super.driveId,
    required super.entityType,
    required super.name,
    required super.txId,
    required super.unixTime,
    required this.drivePrivacy,
    required this.rootFolderId,
  });

  final DrivePrivacy drivePrivacy;
  final String rootFolderId;
}

abstract class ARFSFileEntity extends ARFSEntity {
  ARFSFileEntity({
    required super.appName,
    required super.appVersion,
    required super.arFS,
    required super.driveId,
    required super.entityType,
    required super.name,
    required super.txId,
    required super.unixTime,
    required this.id,
    required this.size,
    required this.lastModifiedDate,
    required this.parentFolderId,
    this.contentType,
  });

  final String id;
  final int size;
  final String parentFolderId;
  final DateTime lastModifiedDate;
  final String? contentType;
}

abstract class ARFSPrivateFileEntity extends ARFSFileEntity
    implements PrivateARFSEntity {
  ARFSPrivateFileEntity({
    required super.appName,
    required super.appVersion,
    required super.arFS,
    required super.contentType,
    required super.driveId,
    required super.entityType,
    required super.name,
    required super.txId,
    required super.unixTime,
    required super.lastModifiedDate,
    required super.parentFolderId,
    required super.size,
    required super.id,
  });
}

class _ARFSFileEntity extends ARFSFileEntity {
  _ARFSFileEntity({
    required super.appName,
    required super.appVersion,
    required super.arFS,
    super.contentType,
    required super.driveId,
    required super.entityType,
    required super.name,
    required super.txId,
    required super.unixTime,
    required super.lastModifiedDate,
    required super.parentFolderId,
    required super.size,
    required super.id,
  });
}

class _ARFSDriveEntity extends ARFSDriveEntity {
  _ARFSDriveEntity({
    required super.appName,
    required super.appVersion,
    required super.arFS,
    required super.driveId,
    required super.entityType,
    required super.name,
    required super.txId,
    required super.unixTime,
    required super.drivePrivacy,
    required super.rootFolderId,
  });
}

enum EntityType { file, folder, drive }

enum DrivePrivacy { public, private }
