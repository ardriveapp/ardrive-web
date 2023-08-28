import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';

abstract class MultiDownloadItem {}

class MultiDownloadFile extends MultiDownloadItem {
  final String driveId;
  final String fileId;
  final String fileName;
  final String txId;
  final int size;

  MultiDownloadFile(
      this.driveId, this.fileId, this.fileName, this.txId, this.size);
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
    multiDownloadFileList.add(MultiDownloadFile(file.driveId, file.id,
        '$folderPath${file.name}', file.dataTxId, file.size));
  }

  return multiDownloadFileList;
}

Future<List<MultiDownloadItem>> convertSelectionToMultiDownloadFileList(
    DriveDao driveDao, List<ArDriveDataTableItem> selectedItems,
    {String path = ''}) async {
  final multiDownloadFileList = <MultiDownloadItem>[];

  for (final item in selectedItems) {
    if (item is FolderDataTableItem) {
      final folderNode = await driveDao.getFolderTree(item.driveId, item.id);

      multiDownloadFileList.addAll(await convertFolderToMultidownloadFileList(
          driveDao, folderNode,
          path: path));
    } else if (item is FileDataTableItem) {
      multiDownloadFileList.add(MultiDownloadFile(
          item.driveId, item.id, item.name, item.dataTxId, item.size!));
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
