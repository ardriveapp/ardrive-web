import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/models.dart';

abstract class FileRepository {
  Future<String> getFilePath(String driveId, String fileId);
  Future<List<FileWithLicenseAndLatestRevisionTransactions>>
      getFilesWithLicenseAndLatestRevisionTransactions(
    String driveId,
    String folderId,
  );

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
}
