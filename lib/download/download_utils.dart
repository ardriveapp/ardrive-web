import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/library/domain/library_mode.dart';
import 'package:ardrive/library/domain/library_scope.dart';
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

/// [folderName] replaces [folderNode]'s own name for this folder only, not
/// its subfolders. Pass the drive's name for a root folder: Rename Drive
/// writes a new drive entity and leaves the root folder's name as it was, so
/// after a rename the root folder's name is the drive's old one.
Future<List<MultiDownloadItem>> convertFolderToMultidownloadFileList(
    DriveDao driveDao, FolderNode folderNode,
    {String path = '', String? folderName}) async {
  final multiDownloadFileList = <MultiDownloadItem>[];

  final folderPath = '$path${folderName ?? folderNode.folder.name}/';

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

  // A library page downloads only what the library shows: the drive behind
  // it holds hidden items and, for a folder library, everything around the
  // folder. Nothing at all before the library is open.
  final library = LibraryMode.isOn ? LibraryContents.open : null;
  if (LibraryMode.isOn && library == null) return multiDownloadFileList;

  for (final item in selectedItems) {
    if (library != null && item is! FileDataTableItem) {
      final folderId =
          item is DriveDataItem ? library.config.scopeRootFolderId : item.id;
      final tree =
          library.prune(await driveDao.getFolderTree(item.driveId, folderId));
      if (tree == null) continue;
      multiDownloadFileList.addAll(await convertFolderToMultidownloadFileList(
        driveDao,
        tree,
        path: path,
        // The library's root is named by its title, as everywhere on the page.
        folderName: folderId == library.config.scopeRootFolderId
            ? library.config.title
            : null,
      ));
    } else if (library != null && item is FileDataTableItem) {
      if (!library.showsFile(item.id)) continue;
      multiDownloadFileList.add(MultiDownloadFile(
        driveId: item.driveId,
        fileId: item.id,
        fileName: item.name,
        txId: item.dataTxId,
        size: item.size!,
        contentType: item.contentType,
        pinnedDataOwnerAddress: item.pinnedDataOwnerAddress,
      ));
    } else if (item is DriveDataItem) {
      final drive = await arfsRepository.getDriveById(item.driveId);
      final folderNode =
          await driveDao.getFolderTree(item.driveId, drive.rootFolderId);

      multiDownloadFileList.addAll(await convertFolderToMultidownloadFileList(
          driveDao, folderNode,
          path: path, folderName: drive.name));
    } else if (item is FolderDataTableItem) {
      final folderNode = await driveDao.getFolderTree(item.driveId, item.id);

      // A guard. The explorer lists a folder's children, so a root folder
      // does not normally arrive here as a folder item, but the item tile
      // allows for one (it names that zip after the drive), and if it does
      // the folder inside must match the zip's name rather than carry the
      // drive's old name.
      final isRootFolder = folderNode.folder.parentFolderId == null;
      final folderName = isRootFolder
          ? (await arfsRepository.getDriveById(item.driveId)).name
          : null;

      multiDownloadFileList.addAll(await convertFolderToMultidownloadFileList(
          driveDao, folderNode,
          path: path, folderName: folderName));
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
