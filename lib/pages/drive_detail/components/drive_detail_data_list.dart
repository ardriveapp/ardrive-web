part of '../drive_detail_page.dart';

Widget _buildDataList(BuildContext context, DriveDetailLoadSuccess state) {
  final folders = state.folderInView.subfolders.map(
    (folder) => DriveDataTableItemMapper.fromFolderEntry(folder, (selected) {
      final bloc = context.read<DriveDetailCubit>();
      if (folder.id == state.maybeSelectedItem()?.id) {
        bloc.openFolder(path: folder.path);
      } else {
        bloc.openFolder(path: folder.path);
      }
    }),
  );

  final files = state.folderInView.files.map(
    (file) =>
        DriveDataTableItemMapper.toFileDataTableItem(file, (selected) async {
      final bloc = context.read<DriveDetailCubit>();
      if (file.id == state.maybeSelectedItem()?.id) {
        bloc.toggleSelectedItemDetails();
      } else {
        await bloc.selectItem(SelectedFile(file: file));
      }
    }),
  );

  return _buildDataListContent(context, [...folders, ...files]);
}

abstract class ArDriveDataTableItem {
  final String name;
  final int? size;
  final DateTime lastUpdated;
  final DateTime dateCreated;
  final String contentType;
  final String? fileStatusFromTransactions;
  final Function(ArDriveDataTableItem) onPressed;
  final String id;
  final String driveId;
  final String path;

  ArDriveDataTableItem({
    required this.id,
    this.size,
    required this.driveId,
    required this.name,
    required this.lastUpdated,
    required this.dateCreated,
    required this.contentType,
    this.fileStatusFromTransactions,
    required this.onPressed,
    required this.path,
  });
}

class FolderDataTableItem extends ArDriveDataTableItem {
  final String? parentFolderId;

  FolderDataTableItem({
    required String driveId,
    required String folderId,
    required String name,
    required DateTime lastUpdated,
    required DateTime dateCreated,
    required String contentType,
    required String path,
    String? fileStatusFromTransactions,
    required Function(ArDriveDataTableItem) onPressed,
    this.parentFolderId,
  }) : super(
          driveId: driveId,
          path: path,
          id: folderId,
          name: name,
          size: null,
          lastUpdated: lastUpdated,
          dateCreated: dateCreated,
          contentType: contentType,
          fileStatusFromTransactions: fileStatusFromTransactions,
          onPressed: onPressed,
        );
}

class FileDataTableItem extends ArDriveDataTableItem {
  final String fileId;
  final String parentFolderId;
  final String dataTxId;
  final String? bundledIn;
  final DateTime lastModifiedDate;
  final NetworkTransaction metadataTx;
  final NetworkTransaction dataTx;

  FileDataTableItem({
    required this.fileId,
    required String driveId,
    required this.parentFolderId,
    required this.dataTxId,
    required DateTime lastUpdated,
    required this.lastModifiedDate,
    required this.metadataTx,
    required this.dataTx,
    required String name,
    required int size,
    required DateTime dateCreated,
    required String contentType,
    required String path,
    String? fileStatusFromTransactions,
    required Function(ArDriveDataTableItem) onPressed,
    this.bundledIn,
  }) : super(
          path: path,
          driveId: driveId,
          id: fileId,
          name: name,
          size: size,
          lastUpdated: lastUpdated,
          dateCreated: dateCreated,
          contentType: contentType,
          fileStatusFromTransactions: fileStatusFromTransactions,
          onPressed: onPressed,
        );
}

Widget _buildDataListContent(
    BuildContext context, List<ArDriveDataTableItem> items) {
  return ArDriveDataTable<ArDriveDataTableItem>(
    key: ValueKey(items),
    rowsPerPageText: appLocalizationsOf(context).rowsPerPage,
    maxItemsPerPage: 100,
    pageItemsDivisorFactor: 25,
    columns: [
      TableColumn('Name', 2),
      TableColumn('Size', 1),
      TableColumn('Last updated', 1),
      TableColumn('Date created', 1),
    ],
    trailing: (file) => DriveExplorerItemTileTrailing(
      item: file,
    ),
    leading: (file) => DriveExplorerItemTileLeading(
      item: file,
    ),
    sortRows: (list, columnIndex, ascDescSort) {
      // Separate folders and files
      List<ArDriveDataTableItem> folders = [];
      List<ArDriveDataTableItem> files = [];

      final lenght = list.length;

      for (int i = 0; i < lenght; i++) {
        if (list[i] is FolderDataTableItem) {
          folders.add(list[i]);
        } else {
          files.add(list[i]);
        }
      }

      // Sort folders and files
      _sortFoldersAndFiles(folders, files, columnIndex, ascDescSort);

      return folders + files;
    },
    buildRow: (row) {
      return DriveExplorerItemTile(
        name: row.name,
        size: row.size == null ? '-' : filesize(row.size),
        lastUpdated: yMMdDateFormatter.format(row.lastUpdated),
        dateCreated: yMMdDateFormatter.format(row.dateCreated),
        onPressed: () => row.onPressed(row),
      );
    },
    rows: items,
  );
}

void _sortFoldersAndFiles(List<ArDriveDataTableItem> folders,
    List<ArDriveDataTableItem> files, int columnIndex, TableSort ascDescSort) {
  _sortItems(folders, columnIndex, ascDescSort);
  _sortItems(files, columnIndex, ascDescSort);
}

int _getResult(int result, TableSort ascDescSort) {
  if (ascDescSort == TableSort.asc) {
    result *= -1;
  }

  return result;
}

void _sortItems(
    List<ArDriveDataTableItem> items, int columnIndex, TableSort ascDescSort) {
  items.sort((a, b) {
    int result = 0;
    if (columnIndex == ColumnIndexes.name) {
      result = compareAlphabeticallyAndNatural(a.name, b.name);
    } else if (columnIndex == ColumnIndexes.size) {
      result = (a.size ?? 0).compareTo(b.size ?? 0);
    } else if (columnIndex == ColumnIndexes.lastUpdated) {
      result = a.lastUpdated.compareTo(b.lastUpdated);
    } else {
      result = a.dateCreated.compareTo(b.dateCreated);
    }
    return _getResult(result, ascDescSort);
  });
}

class ColumnIndexes {
  static const int name = 0;
  static const int size = 1;
  static const int lastUpdated = 2;
  static const int dateCreated = 3;
}

class DriveDataTableItemMapper {
  static FileDataTableItem toFileDataTableItem(
      FileWithLatestRevisionTransactions file,
      Function(ArDriveDataTableItem) onPressed) {
    return FileDataTableItem(
      path: file.path,
      lastModifiedDate: file.lastModifiedDate,
      name: file.name,
      size: file.size,
      lastUpdated: file.lastUpdated,
      dateCreated: file.dateCreated,
      contentType: file.dataContentType ?? '',
      fileStatusFromTransactions: fileStatusFromTransactions(
        file.metadataTx,
        file.dataTx,
      ).toString(),
      fileId: file.id,
      onPressed: onPressed,
      driveId: file.driveId,
      parentFolderId: file.parentFolderId,
      dataTxId: file.dataTxId,
      bundledIn: file.bundledIn,
      metadataTx: file.metadataTx,
      dataTx: file.dataTx,
    );
  }

  static FolderDataTableItem fromFolderEntry(
      FolderEntry folderEntry, Function(ArDriveDataTableItem) onPressed) {
    return FolderDataTableItem(
      path: folderEntry.path,
      driveId: folderEntry.driveId,
      folderId: folderEntry.id,
      parentFolderId: folderEntry.parentFolderId,
      name: folderEntry.name,
      lastUpdated: folderEntry.lastUpdated,
      dateCreated: folderEntry.dateCreated,
      contentType: 'folder',
      fileStatusFromTransactions: null,
      onPressed: onPressed,
    );
  }
}
