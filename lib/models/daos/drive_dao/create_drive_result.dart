part of 'drive_dao.dart';

class CreateDriveResult {
  final String driveId;
  final String rootFolderId;
  final SecretKey driveKey;

  CreateDriveResult(this.driveId, this.rootFolderId, this.driveKey);
}
