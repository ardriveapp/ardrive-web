import 'package:ardrive/core/arfs/exceptions.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:drift/drift.dart';

abstract class FolderRepository {
  Future<FolderEntry> getFolderEntryById(String folderId);
  Future<FolderNode> getFolderNode(String driveId, String folderId);
  Future<FolderRevision?> getLatestFolderRevisionInfo(
      String driveId, String folderId);
  Future<String> getFolderPath(String driveId, String folderId);
  Stream<FolderWithContents> watchFolderContents({
    required String driveId,
    required String folderId,
    DriveOrder orderBy = DriveOrder.name,
    OrderingMode orderingMode = OrderingMode.asc,
  });
  Future<List<FileEntry>> existingFilesWithName({
    required String name,
    required String parentFolderId,
    required String driveId,
  });
  Future<List<FolderEntry>> existingFoldersWithName({
    required String name,
    required String parentFolderId,
    required String driveId,
  });

  /// Checks for folder name conflicts in the target folder
  ///
  /// Returns a list of [FolderConflict] objects containing information about any conflicting folders
  Future<List<FolderConflict>> checkFolderConflicts({
    required String driveId,
    required String parentFolderId,
    required String folderName,
  });

  /// Checks for folder name conflicts across the entire folder tree
  ///
  /// Returns a map of folder paths to their conflicts
  Future<Map<String, List<FolderConflict>>> checkFolderTreeConflicts({
    required String driveId,
    required String rootFolderId,
    required List<String> folderPaths,
  });

  factory FolderRepository(DriveDao driveDao) => _FolderRepository(driveDao);
}

/// Represents a folder conflict in the system
class FolderConflict {
  final String folderId;
  final String folderName;
  final String? parentFolderId;

  FolderConflict({
    required this.folderId,
    required this.folderName,
    this.parentFolderId,
  });
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

  // TODO: implement unit tests for this method
  @override
  Stream<FolderWithContents> watchFolderContents({
    required String driveId,
    required String folderId,
    DriveOrder orderBy = DriveOrder.name,
    OrderingMode orderingMode = OrderingMode.asc,
  }) {
    return _driveDao.watchFolderContents(
      driveId,
      folderId: folderId,
      orderBy: orderBy,
      orderingMode: orderingMode,
    );
  }

  @override
  Future<FolderNode> getFolderNode(String driveId, String folderId) {
    return _driveDao.getFolderTree(driveId, folderId);
  }

  // TODO: implement unit tests for this method
  @override
  Future<List<FileEntry>> existingFilesWithName({
    required String name,
    required String parentFolderId,
    required String driveId,
  }) async {
    final files = await _driveDao
        .filesInFolderWithName(
            name: name, parentFolderId: parentFolderId, driveId: driveId)
        .get();

    if (files.length > 1) {
      /// It should not happen, but it's a possible case.
      logger.e(
        'Error checking for file name conflictics.',
        ARFSMultipleNamesForTheSameEntityException(),
      );
    }

    return files;
  }

  // TODO: implement unit tests for this method
  @override
  Future<List<FolderEntry>> existingFoldersWithName({
    required String name,
    required String parentFolderId,
    required String driveId,
  }) async {
    final folders = await _driveDao
        .foldersInFolderWithName(
            name: name, parentFolderId: parentFolderId, driveId: driveId)
        .get();

    if (folders.length > 1) {
      /// It should not happen, but it's a possible case.
      logger.e(
        'Error checking for folder name conflictics.',
        ARFSMultipleNamesForTheSameEntityException(),
      );
    }

    return folders;
  }

  @override
  Future<FolderEntry> getFolderEntryById(String folderId) {
    return _driveDao.folderById(folderId: folderId).getSingle();
  }

  @override
  Future<List<FolderConflict>> checkFolderConflicts({
    required String driveId,
    required String parentFolderId,
    required String folderName,
  }) async {
    final existingFolders = await _driveDao
        .foldersInFolderWithName(
          driveId: driveId,
          parentFolderId: parentFolderId,
          name: folderName,
        )
        .get();

    return existingFolders
        .map(
          (folder) => FolderConflict(
            folderId: folder.id,
            folderName: folder.name,
            parentFolderId: folder.parentFolderId,
          ),
        )
        .toList();
  }

  @override
  Future<Map<String, List<FolderConflict>>> checkFolderTreeConflicts({
    required String driveId,
    required String rootFolderId,
    required List<String> folderPaths,
  }) async {
    final conflicts = <String, List<FolderConflict>>{};

    for (final path in folderPaths) {
      final pathComponents = path.split('/');
      var currentFolderId = rootFolderId;

      for (final component in pathComponents) {
        if (component.isEmpty) continue;

        final folderConflicts = await checkFolderConflicts(
          driveId: driveId,
          parentFolderId: currentFolderId,
          folderName: component,
        );

        if (folderConflicts.isNotEmpty) {
          conflicts[path] = folderConflicts;
          break;
        }

        // Get the existing folder ID to continue traversing
        final existingFolder = await _driveDao
            .foldersInFolderWithName(
              driveId: driveId,
              parentFolderId: currentFolderId,
              name: component,
            )
            .getSingleOrNull();

        if (existingFolder != null) {
          currentFolderId = existingFolder.id;
        }
      }
    }

    return conflicts;
  }
}
