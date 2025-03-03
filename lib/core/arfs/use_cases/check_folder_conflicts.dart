import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as path;

/// Input model for file conflict checking
class FileConflictCheck extends Equatable {
  final String name;
  final String path;
  final String parentFolderId;
  final String id;

  const FileConflictCheck({
    required this.name,
    required this.path,
    required this.parentFolderId,
    required this.id,
  });

  @override
  List<Object?> get props => [name, path, parentFolderId, id];
}

/// Represents a file conflict with its location in the folder tree
class FileTreeConflict extends Equatable {
  final String filePath;
  final String fileName;
  final String
      parentFolderId; // The ID of the parent folder where the file exists
  final String existingFileId; // The ID of the conflicting file
  final String newFileId;

  const FileTreeConflict({
    required this.filePath,
    required this.fileName,
    required this.parentFolderId,
    required this.existingFileId,
    required this.newFileId,
  });

  @override
  List<Object?> get props =>
      [filePath, fileName, parentFolderId, existingFileId];
}

/// Result of checking for conflicts in the folder tree
class FolderConflictResult extends Equatable {
  final List<FileTreeConflict> conflicts;
  final bool hasConflicts;

  const FolderConflictResult({
    required this.conflicts,
    required this.hasConflicts,
  });

  @override
  List<Object?> get props => [conflicts, hasConflicts];
}

/// Checks for file conflicts in the folder tree
///
/// Returns a [FolderConflictResult] containing information about conflicting files
/// and their parent folder IDs
class CheckFolderConflicts {
  final FolderRepository _folderRepository;
  final FileRepository _fileRepository;

  CheckFolderConflicts(this._folderRepository, this._fileRepository);

  Future<FolderConflictResult> call({
    required String driveId,
    required String targetFolderId,
    required List<FileConflictCheck> files,
  }) async {
    final conflicts = <FileTreeConflict>[];

    // Build folder paths map to track parent folder IDs
    final folderIdsByPath = <String, String>{};
    folderIdsByPath['.'] = targetFolderId;

    // Process each file's path to check for folder conflicts
    for (final file in files) {
      final pathComponents = path.split(file.path)
        ..removeWhere((component) => component.isEmpty);
      var currentPath = '';
      var currentFolderId = targetFolderId;

      // Check each folder in the path
      for (var i = 0; i < pathComponents.length - 1; i++) {
        final folderName = pathComponents[i];
        currentPath = path.join(currentPath, folderName);

        // Check if we already found this folder's ID
        if (!folderIdsByPath.containsKey(currentPath)) {
          final existingFolders =
              await _folderRepository.existingFoldersWithName(
            driveId: driveId,
            parentFolderId: currentFolderId,
            name: folderName,
          );

          if (existingFolders.isNotEmpty) {
            currentFolderId = existingFolders.first.id;
            folderIdsByPath[currentPath] = currentFolderId;
          } else {
            // If folder doesn't exist, we can't have conflicts in this path
            break;
          }
        } else {
          currentFolderId = folderIdsByPath[currentPath]!;
        }
      }

      // Check for file conflicts in the final folder
      final parentFolderPath = path.dirname(file.path);
      final parentFolderId =
          folderIdsByPath[parentFolderPath] ?? targetFolderId;

      final existingFiles = await _fileRepository.checkFileConflicts(
        driveId: driveId,
        parentFolderId: parentFolderId,
        fileName: file.name,
      );

      for (final conflict in existingFiles) {
        conflicts.add(
          FileTreeConflict(
            filePath: file.path,
            fileName: file.name,
            parentFolderId: parentFolderId,
            existingFileId: conflict.fileId,
            newFileId: file.id,
          ),
        );
      }
    }

    return FolderConflictResult(
      conflicts: conflicts,
      hasConflicts: conflicts.isNotEmpty,
    );
  }
}
