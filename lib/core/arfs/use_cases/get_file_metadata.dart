import 'package:ardrive/core/arfs/repository/file_metadata_repository.dart';
import 'package:ardrive/utils/logger.dart';

/// Use case for retrieving file metadata from Arweave.
class GetFileMetadata {
  final FileMetadataRepository _repository;

  GetFileMetadata(this._repository);

  /// Fetches metadata for a list of files from Arweave.
  ///
  /// Returns a [FileMetadataResult] containing the metadata for each file and any failures.
  Future<FileMetadataResult> call(List<String> fileIds) async {
    logger.i('Fetching metadata for ${fileIds.length} files');
    return _repository.getFileMetadata(fileIds);
  }

  /// Fetches metadata for a single file from Arweave.
  ///
  /// Returns the [FileMetadata] if successful, null if not found or on error.
  Future<FileMetadata?> getMetadataForFile(String fileId) async {
    logger.i('Fetching metadata for file: $fileId');

    final result = await _repository.getFileMetadata([fileId]);

    if (result.failures.isNotEmpty) {
      logger.e(
          'Failed to fetch metadata for file: $fileId', result.failures.first);
      return null;
    }

    return result.metadata[fileId];
  }
}
