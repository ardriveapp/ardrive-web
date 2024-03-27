import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';

abstract class FolderRepository {
  Future<FolderRevision?> getLatestFolderRevisionInfo(
      String driveId, String folderId);
  Future<String> getFolderPath(String driveId, String folderId);

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

  @override
  Future<String> getFolderPath(String driveId, String folderId) async {
    // Initialize an empty list to hold each folder's name as we traverse up the hierarchy
    final List<String> pathComponents = [];

    // Current folder ID that we will be checking
    String? currentFolderId = folderId;

    while (currentFolderId != null) {
      // Retrieve the folder by its ID
      final folder = await _driveDao
          .latestFolderRevisionByFolderId(
              driveId: driveId, folderId: currentFolderId)
          .getSingleOrNull();

      // If the folder is null (not found), break out of the loop to avoid an infinite loop
      if (folder == null) {
        break;
      }

      // Prepend the folder's name to the path components list
      // Assuming 'name' is the property where the folder's name is stored
      pathComponents.insert(0, folder.name);

      // Move up to the parent folder for the next iteration
      currentFolderId = folder.parentFolderId;
    }

    // Join all path components with '/' to create the full path
    // This will correctly handle the scenario when pathComponents is empty
    return pathComponents.join('/');
  }
}
