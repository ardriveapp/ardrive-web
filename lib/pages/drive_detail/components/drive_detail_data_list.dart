part of '../drive_detail_page.dart';

Widget _buildDataList(BuildContext context, DriveDetailLoadSuccess state) {
  List<ArDriveDataTableItem> items = [];

  // add folders to items mapping to the correct object
  items.addAll(
    state.folderInView.subfolders.map(
      (folder) => ArDriveDataTableItem(
        onPressed: (selected) {
          final bloc = context.read<DriveDetailCubit>();
          if (folder.id == state.maybeSelectedItem()?.id) {
            bloc.openFolder(path: folder.path);
          } else {
            bloc.openFolder(path: folder.path);
          }
        },
        name: folder.name,
        lastUpdated: folder.lastUpdated,
        dateCreated: folder.dateCreated,
        type: 'folder',
        contentType: 'folder',
      ),
    ),
  );

  // add files to items mapping to the correct object
  items.addAll(
    state.folderInView.files.map(
      (file) => ArDriveDataTableItem(
          name: file.name,
          size: filesize(file.size),
          fileStatusFromTransactions: fileStatusFromTransactions(
            file.metadataTx,
            file.dataTx,
          ).toString(),
          type: 'file',
          contentType: file.dataContentType ?? 'octet-stream',
          lastUpdated: file.lastUpdated,
          dateCreated: file.dateCreated,
          onPressed: (item) async {
            final bloc = context.read<DriveDetailCubit>();
            if (file.id == state.maybeSelectedItem()?.id) {
              bloc.toggleSelectedItemDetails();
            } else {
              await bloc.selectItem(SelectedFile(file: file));
            }
          }),
    ),
  );

  return _buildDataListContent(context, items);
}

class ArDriveDataTableItem {
  final String name;
  final String size;
  final DateTime lastUpdated;
  final DateTime dateCreated;
  final String type;
  final String contentType;
  final String? fileStatusFromTransactions;
  final Function(ArDriveDataTableItem) onPressed;

  ArDriveDataTableItem({
    required this.name,
    this.size = '-',
    required this.lastUpdated,
    required this.dateCreated,
    required this.type,
    required this.contentType,
    this.fileStatusFromTransactions,
    required this.onPressed,
  });
}

Widget _buildDataListContent(
    BuildContext context, List<ArDriveDataTableItem> items) {
  return ArDriveDataTable<ArDriveDataTableItem>(
    key: ValueKey(items.length),
    rowsPerPageText: appLocalizationsOf(context).rowsPerPage,
    maxItemsPerPage: 100,
    pageItemsDivisorFactor: 25,
    columns: [
      TableColumn('Name', 2),
      TableColumn('Size', 1),
      TableColumn('Last updated', 1),
      TableColumn('Date created', 1),
    ],
    leading: (file) => DriveExplorerItemTileLeading(
      item: file,
    ),
    sortRows: (list, columnIndex, sortOrder) {
      // Separate folders and files
      List<ArDriveDataTableItem> folders = [];
      List<ArDriveDataTableItem> files = [];

      for (int i = 0; i < list.length; i++) {
        if (list[i].type == 'folder') {
          folders.add(list[i]);
        } else {
          files.add(list[i]);
        }
      }

      // Sort folders and files
      _sortFoldersAndFiles(folders, files, columnIndex, sortOrder);

      return folders + files;
    },
    buildRow: (row) {
      return DriveExplorerItemTile(
        name: row.name,
        size: row.size,
        lastUpdated: yMMdDateFormatter.format(row.lastUpdated),
        dateCreated: yMMdDateFormatter.format(row.dateCreated),
        onPressed: () => row.onPressed(row),
      );
    },
    rows: items,
  );
}

void _sortFoldersAndFiles(List<ArDriveDataTableItem> folders,
    List<ArDriveDataTableItem> files, int columnIndex, TableSort sortOrder) {
  _sortItems(folders, columnIndex, sortOrder);
  _sortItems(files, columnIndex, sortOrder);
}

int _getResult(int result, TableSort sortOrder) {
  if (sortOrder == TableSort.asc) {
    result *= -1;
  }

  return result;
}

void _sortItems(List items, int columnIndex, TableSort sortOrder) {
  items.sort((a, b) {
    int result = 0;
    if (columnIndex == ColumnIndexes.name) {
      result = compareAlphabeticallyAndNatural(a.name, b.name);
    } else if (columnIndex == ColumnIndexes.size) {
      result = a.size.compareTo(b.size);
    } else if (columnIndex == ColumnIndexes.lastUpdated) {
      result = a.lastUpdated.compareTo(b.lastUpdated);
    } else {
      result = a.dateCreated.compareTo(b.dateCreated);
    }
    return _getResult(result, sortOrder);
  });
}

class ColumnIndexes {
  static const int name = 0;
  static const int size = 1;
  static const int lastUpdated = 2;
  static const int dateCreated = 3;
}
