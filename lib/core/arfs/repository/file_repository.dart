import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';

abstract class FileRepository {
  Future<String> getFilePath(String driveId, String fileId);
  Future<List<FileWithLicenseAndLatestRevisionTransactions>>
      getFilesWithLicenseAndLatestRevisionTransactions(
    String driveId,
    String folderId,
  );

  Future<FileEntry> getFileEntryById(String fileId);

  /// Updates a file entry in the database.
  ///
  /// This method updates a file entry in the database. It takes a generic
  /// parameter [T] which can be either a [FileEntry] or a [FileEntity].
  /// The method then calls the appropriate DAO method to update the file entry.
  Future<void> updateFile<T>(T fileEntry);

  Future<void> updateFileRevision(FileEntity fileEntity, String revision);

  Future<FileRevision> getLatestFileRevision(String driveId, String fileId);

  /// Checks if a file with the given name exists in the specified folder
  ///
  /// Returns a list of [FileConflict] objects containing information about any conflicting files
  Future<List<FileConflict>> checkFileConflicts({
    required String driveId,
    required String parentFolderId,
    required String fileName,
  });

  /// Checks if a file has failed uploads
  ///
  /// Returns true if the file has any failed upload transactions
  Future<bool> hasFailedUploads({
    required String driveId,
    required String fileId,
  });

  factory FileRepository(
          DriveDao driveDao, FolderRepository folderRepository) =>
      _FileRepository(
        driveDao,
        folderRepository,
      );
}

/// Represents a file conflict in the system
class FileConflict {
  final String fileId;
  final String fileName;
  final String dataTxId;

  FileConflict({
    required this.fileId,
    required this.fileName,
    required this.dataTxId,
  });
}

class _FileRepository implements FileRepository {
  final DriveDao _driveDao;
  final FolderRepository _folderRepository;

  _FileRepository(this._driveDao, this._folderRepository);

  @override
  Future<String> getFilePath(String driveId, String fileId) async {
    final file = await _driveDao
        .latestFileRevisionByFileId(driveId: driveId, fileId: fileId)
        .getSingleOrNull();

    if (file == null) {
      return '';
    }

    final folderPath =
        await _folderRepository.getFolderPath(driveId, file.parentFolderId);
    final filePath = '$folderPath/${file.name}';
    return filePath;
  }

  // TODO: implement unit tests for this method
  @override
  Future<List<FileWithLicenseAndLatestRevisionTransactions>>
      getFilesWithLicenseAndLatestRevisionTransactions(
          String driveId, String folderId) {
    return _driveDao
        .filesInFolderWithLicenseAndRevisionTransactions(
            driveId: driveId, parentFolderId: folderId)
        .get();
  }

  @override
  Future<FileEntry> getFileEntryById(String fileId) {
    return _driveDao.fileById(fileId: fileId).getSingle();
  }

  @override
  Future<void> updateFile<T>(T fileEntry) async {
    if (fileEntry is FileEntry) {
      await _driveDao.writeFileEntity(fileEntry.asEntity());
    } else if (fileEntry is FileEntity) {
      await _driveDao.writeFileEntity(fileEntry);
    }
  }

  @override
  Future<void> updateFileRevision(FileEntity fileEntity, String revision) {
    return _driveDao.insertFileRevision(
      fileEntity.toRevisionCompanion(
        performedAction: revision,
      ),
    );
  }

  @override
  Future<FileRevision> getLatestFileRevision(String driveId, String fileId) {
    return _driveDao
        .latestFileRevisionByFileId(
          driveId: driveId,
          fileId: fileId,
        )
        .getSingle();
  }

  @override
  Future<List<FileConflict>> checkFileConflicts({
    required String driveId,
    required String parentFolderId,
    required String fileName,
  }) async {
    final existingFiles = await _driveDao
        .filesInFolderWithName(
          driveId: driveId,
          parentFolderId: parentFolderId,
          name: fileName,
        )
        .get();

    final conflicts = <FileConflict>[];

    for (final file in existingFiles) {
      final latestRevision = await _driveDao
          .latestFileRevisionByFileId(
            driveId: driveId,
            fileId: file.id,
          )
          .getSingleOrNull();

      if (latestRevision != null) {
        conflicts.add(
          FileConflict(
            fileId: file.id,
            fileName: file.name,
            dataTxId: latestRevision.dataTxId,
          ),
        );
      }
    }

    return conflicts;
  }

  @override
  Future<bool> hasFailedUploads({
    required String driveId,
    required String fileId,
  }) async {
    final latestRevision = await _driveDao
        .latestFileRevisionByFileId(
          driveId: driveId,
          fileId: fileId,
        )
        .getSingleOrNull();

    if (latestRevision == null) {
      return false;
    }

    final transaction = await (_driveDao.select(_driveDao.networkTransactions)
          ..where((tbl) => tbl.id.equals(latestRevision.dataTxId)))
        .getSingleOrNull();

    return transaction?.status == TransactionStatus.failed;
  }
}
