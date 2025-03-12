import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';

class FileConflictResult extends Equatable {
  final Map<String, String> conflictingFiles;
  final List<String> failedFiles;
  final bool hasConflicts;

  const FileConflictResult({
    required this.conflictingFiles,
    required this.failedFiles,
    required this.hasConflicts,
  });

  @override
  List<Object?> get props => [conflictingFiles, failedFiles, hasConflicts];
}

/// Checks for file conflicts in the target folder
///
/// Returns a [FileConflictResult] containing information about conflicting files
/// and any failed uploads
class CheckFileConflicts {
  final FileRepository _fileRepository;

  CheckFileConflicts(this._fileRepository);

  Future<FileConflictResult> call({
    required String driveId,
    required List<UploadFile> files,
    bool checkFailedFiles = true,
  }) async {
    final Map<String, String> conflictingFiles = {};
    final List<String> failedFiles = [];

    // Check for file name conflicts
    for (final file in files) {
      final conflicts = await _fileRepository.checkFileConflicts(
        driveId: driveId,
        parentFolderId: file.parentFolderId,
        fileName: file.ioFile.name,
      );

      if (conflicts.isNotEmpty) {
        logger.d(
            'Found conflicting file. Existing file id: ${conflicts.first.fileId}');
        conflictingFiles[file.getIdentifier()] = conflicts.first.fileId;
      }
    }

    // If there are conflicts and we need to check for failed files
    if (conflictingFiles.isNotEmpty && checkFailedFiles) {
      for (final fileNameKey in conflictingFiles.keys) {
        final fileId = conflictingFiles[fileNameKey];
        final hasFailed = await _fileRepository.hasFailedUploads(
          driveId: driveId,
          fileId: fileId!,
        );

        if (hasFailed) {
          logger.d('Found failed upload for file: $fileNameKey');
          failedFiles.add(fileNameKey);
        }
      }
    }

    return FileConflictResult(
      conflictingFiles: conflictingFiles,
      failedFiles: failedFiles,
      hasConflicts: conflictingFiles.isNotEmpty,
    );
  }
}
