import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';

abstract class FolderRepository {
  Future<FolderRevision?> getLatestFolderRevisionInfo(
      String driveId, String folderId);

  factory FolderRepository(DriveDao driveDao) => _FolderRepository(driveDao);
}

class _FolderRepository implements FolderRepository {
  final DriveDao _driveDao;

  _FolderRepository(this._driveDao);

  @override
  Future<FolderRevision?> getLatestFolderRevisionInfo(
      String driveId, String folderId) async {
    return await _driveDao
        .latestFolderRevisionByFolderId(driveId: driveId, folderId: folderId)
        .getSingleOrNull();
  }
}
