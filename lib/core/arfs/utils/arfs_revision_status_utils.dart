import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/enums.dart';

class ARFSRevisionStatusUtils {
  final FileRepository _fileRepository;

  ARFSRevisionStatusUtils(this._fileRepository);

  Future<bool> hasPendingFilesOnTargetFolder({
    required FolderNode folderNode,
  }) async {
    final files = folderNode.getRecursiveFiles();
    final folders = folderNode.subfolders;

    if (files.isEmpty && folders.isEmpty) {
      return false;
    }

    final filesWithTx =
        await _fileRepository.getFilesWithLicenseAndLatestRevisionTransactions(
      folderNode.folder.driveId,
      folderNode.folder.id,
    );

    final hasPendingFiles = filesWithTx.any((e) =>
        TransactionStatus.pending ==
        fileStatusFromTransactions(
          e.metadataTx,
          e.dataTx,
        ).toString());

    if (hasPendingFiles) {
      return true;
    }

    for (var folder in folders) {
      if (await hasPendingFilesOnTargetFolder(folderNode: folder)) {
        return true;
      }
    }

    return false;
  }
}
