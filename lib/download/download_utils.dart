import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';

abstract class MultiDownloadItem {}

class MultiDownloadFile extends MultiDownloadItem {
  final String driveId;
  final String fileId;
  final String fileName;
  final String txId;
  final String? contentType;
  final int size;
  final String? pinnedDataOwnerAddress;

  MultiDownloadFile({
    required this.driveId,
    required this.fileId,
    required this.fileName,
    required this.txId,
    required this.size,
    this.contentType,
    this.pinnedDataOwnerAddress,
  });
}

class MultiDownloadFolder extends MultiDownloadItem {
  final String folderPath;

  MultiDownloadFolder(this.folderPath);
}

Future<List<MultiDownloadItem>> convertFolderToMultidownloadFileList(
    DriveDao driveDao, FolderNode folderNode,
    {String path = ''}) async {
  final multiDownloadFileList = <MultiDownloadItem>[];

  final folderPath = '$path${folderNode.folder.name}/';

  multiDownloadFileList.add(MultiDownloadFolder(folderPath));

  for (final subFolder in folderNode.subfolders) {
    multiDownloadFileList.addAll(await convertFolderToMultidownloadFileList(
        driveDao, subFolder,
        path: folderPath));
  }

  for (final file in folderNode.files.values) {
    multiDownloadFileList.add(MultiDownloadFile(
      driveId: file.driveId,
      fileId: file.id,
      fileName: '$folderPath${file.name}',
      txId: file.dataTxId,
      size: file.size,
      contentType: file.dataContentType,
      pinnedDataOwnerAddress: file.pinnedDataOwnerAddress,
    ));
  }

  return multiDownloadFileList;
}

Future<List<MultiDownloadItem>> convertSelectionToMultiDownloadFileList(
    DriveDao driveDao,
    ARFSRepository arfsRepository,
    List<ArDriveDataTableItem> selectedItems,
    {String path = ''}) async {
  final multiDownloadFileList = <MultiDownloadItem>[];

  for (final item in selectedItems) {
    if (item is DriveDataItem) {
      final drive = await arfsRepository.getDriveById(item.driveId);
      final folderNode =
          await driveDao.getFolderTree(item.driveId, drive.rootFolderId);

      multiDownloadFileList.addAll(await convertFolderToMultidownloadFileList(
          driveDao, folderNode,
          path: path));
    } else if (item is FolderDataTableItem) {
      final folderNode = await driveDao.getFolderTree(item.driveId, item.id);

      multiDownloadFileList.addAll(await convertFolderToMultidownloadFileList(
          driveDao, folderNode,
          path: path));
    } else if (item is FileDataTableItem) {
      multiDownloadFileList.add(MultiDownloadFile(
        driveId: item.driveId,
        fileId: item.id,
        fileName: item.name,
        txId: item.dataTxId,
        size: item.size!,
        contentType: item.contentType,
        pinnedDataOwnerAddress: item.pinnedDataOwnerAddress,
      ));
    }
  }

  return multiDownloadFileList;
}

int calculateTotalFileSize(
    DriveDao driveDao, List<MultiDownloadItem> selectedItems) {
  return selectedItems.fold(0, (previousValue, element) {
    return element is MultiDownloadFile
        ? previousValue + element.size
        : previousValue;
  });
}
