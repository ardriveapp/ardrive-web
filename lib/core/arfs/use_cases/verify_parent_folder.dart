import 'package:ardrive/models/models.dart';

/// Exception thrown when a parent folder verification fails.
class ParentFolderVerificationException implements Exception {
  final String message;
  final String? folderId;

  ParentFolderVerificationException(this.message, {this.folderId});

  @override
  String toString() =>
      'ParentFolderVerificationException: $message${folderId != null ? ' (Folder ID: $folderId)' : ''}';
}

/// Use case for verifying parent folder IDs.
class VerifyParentFolder {
  final DriveDao _driveDao;

  VerifyParentFolder(this._driveDao);

  /// Verifies that a parent folder exists and is accessible.
  ///
  /// Takes a [driveId] and [parentFolderId] and verifies that:
  /// 1. The folder exists in the database
  /// 2. The folder belongs to the specified drive
  /// 3. The folder is accessible (not deleted or corrupted)
  ///
  /// If [folderName] is provided, it will also check for a folder with that name
  /// under the parent folder and return it if found.
  ///
  /// Returns the [FolderEntry] if verification is successful.
  /// Throws [ParentFolderVerificationException] if verification fails.
  Future<FolderEntry> call({
    required String driveId,
    required String parentFolderId,
    String? folderName,
  }) async {
    try {
      // If folderName is provided, try to find an existing folder with that name
      if (folderName != null) {
        final existingFolder = await _driveDao
            .foldersInFolderWithName(
              driveId: driveId,
              parentFolderId: parentFolderId,
              name: folderName,
            )
            .getSingleOrNull();

        if (existingFolder != null) {
          return existingFolder;
        }
      }

      // Attempt to fetch the folder from the database
      final folder = await _driveDao
          .folderById(folderId: parentFolderId)
          .getSingleOrNull();

      // Check if the folder exists
      if (folder == null) {
        throw ParentFolderVerificationException(
          'Parent folder not found',
          folderId: parentFolderId,
        );
      }

      // Check if the folder belongs to the specified drive
      if (folder.driveId != driveId) {
        throw ParentFolderVerificationException(
          'Parent folder belongs to a different drive',
          folderId: parentFolderId,
        );
      }

      // Get the latest revision to check folder status
      final latestRevision = await _driveDao
          .latestFolderRevisionByFolderId(
            driveId: driveId,
            folderId: parentFolderId,
          )
          .getSingleOrNull();

      // Check if the folder has a valid latest revision
      if (latestRevision == null) {
        throw ParentFolderVerificationException(
          'Parent folder has no valid revision',
          folderId: parentFolderId,
        );
      }

      return folder;
    } catch (e) {
      if (e is ParentFolderVerificationException) {
        rethrow;
      }
      throw ParentFolderVerificationException(
        'Failed to verify parent folder: ${e.toString()}',
        folderId: parentFolderId,
      );
    }
  }
}
