import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/logger.dart';

abstract class FileRepository {
  Future<String> getFilePath(String driveId, String fileId);
  Future<List<FileWithLicenseAndLatestRevisionTransactions>>
      getFilesWithLicenseAndLatestRevisionTransactions(
    String driveId,
    String folderId,
  );

  Future<FileEntry> getFileEntryById(String driveId, String fileId);
  Future<void> updateFile(FileEntry fileEntry);
  Future<void> updateFileRevision(FileEntity fileEntity, String revision);
  Future<FileRevision> getLatestFileRevision(String driveId, String fileId);

  factory FileRepository(
          DriveDao driveDao, FolderRepository folderRepository) =>
      _FileRepository(
        driveDao,
        folderRepository,
      );
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
  Future<FileEntry> getFileEntryById(String driveId, String fileId) {
    return _driveDao.fileById(driveId: driveId, fileId: fileId).getSingle();
  }

  @override
  Future<void> updateFile(FileEntry fileEntry) {
    return _driveDao.writeToFile(fileEntry);
  }

  @override
  Future<void> updateFileRevision(FileEntity fileEntity, String revision) {
    logger.d('Updating file revision: $revision');

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
}
