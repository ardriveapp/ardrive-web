import 'package:ardrive/core/arfs/repository/file_metadata_repository.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:drift/drift.dart';

/// Exception thrown when file metadata insertion fails.
class FileMetadataInsertionException implements Exception {
  final String message;
  final String? fileId;
  final dynamic originalError;

  FileMetadataInsertionException(
    this.message, {
    this.fileId,
    this.originalError,
  });

  @override
  String toString() =>
      'FileMetadataInsertionException: $message${fileId != null ? ' (File ID: $fileId)' : ''}${originalError != null ? '\nOriginal error: $originalError' : ''}';
}

/// Use case for inserting file metadata into the database.
class InsertFileMetadata {
  final DriveDao _driveDao;

  InsertFileMetadata(this._driveDao);

  /// Inserts file metadata into the database.
  ///
  /// Takes a [FileMetadata] object and inserts or updates the corresponding
  /// file entry and revision in the database.
  ///
  /// Returns the inserted/updated [FileEntry].
  /// Throws [FileMetadataInsertionException] if insertion fails.
  Future<FileEntry> call(
    FileMetadata metadata, {
    required String driveId,
    required String parentFolderId,
  }) async {
    try {
      // Check if the file already exists
      final existingFile =
          await _driveDao.fileById(fileId: metadata.id).getSingleOrNull();

      // Create or update the file entity
      final fileEntity = FileEntity(
        driveId: driveId,
        name: metadata.name,
        size: metadata.size,
        lastModifiedDate: metadata.lastModifiedDate,
        dataTxId: metadata.dataTxId,
        dataContentType: metadata.contentType,
        parentFolderId: parentFolderId,
        id: metadata.id,
      );

      // Create a new revision companion
      final fileRevision = FileRevisionsCompanion(
        driveId: Value(driveId),
        fileId: Value(metadata.id),
        action: Value(existingFile != null ? 'update' : 'create'),
        name: Value(metadata.name),
        size: Value(metadata.size),
        dateCreated: Value(DateTime.now()),
        lastModifiedDate: Value(metadata.lastModifiedDate),
        dataContentType: Value(metadata.contentType),
        dataTxId: Value(metadata.dataTxId),
        parentFolderId: Value(parentFolderId),
        metadataTxId: const Value(''), // This will be set by the caller
        isHidden: const Value(false),
      );

      // Perform the database transaction
      await _driveDao.transaction(() async {
        // Insert or update the file entity
        await _driveDao.writeFileEntity(fileEntity);

        // Insert the new revision
        await _driveDao.insertFileRevision(fileRevision);
      });

      // Return the updated file entry
      final updatedFile =
          await _driveDao.fileById(fileId: metadata.id).getSingle();
      return updatedFile;
    } catch (e) {
      logger.e('Failed to insert file metadata', e);
      throw FileMetadataInsertionException(
        'Failed to insert file metadata',
        fileId: metadata.id,
        originalError: e,
      );
    }
  }
}
