part of '../drive_detail_page.dart';

Widget _buildDataList(BuildContext context, DriveDetailLoadSuccess state) {
  List<ArDriveDataTableItem> items = [];

  int index = 0;

  // add folders to items mapping to the correct object
  items.addAll(state.folderInView.subfolders.map(
    (folder) => ArDriveDataTableItem(
      index: index++,
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
  ));

  // add files to items mapping to the correct object
  items.addAll(state.folderInView.files.map(
    (file) => ArDriveDataTableItem(
        index: index++,
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
  ));

  return _buildDataListContent(context, items);
}

class ArDriveDataTableItem extends IndexedItem {
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
    required int index,
  }) : super(index);
}

Widget _buildDataListContent(
    BuildContext context, List<ArDriveDataTableItem> items) {
  return ArDriveDataTable<ArDriveDataTableItem>(
    onSelectedRows: (rows) {
      for (final row in rows) {
        print(row.name);
      }
    },
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
    sort: (columnIndex) {
      int sort(ArDriveDataTableItem a, ArDriveDataTableItem b) {
        // TODO(add folders in the start of the list)
        if (columnIndex == 0) {
          return compareAlphabeticallyAndNatural(a.name, b.name);
        } else if (columnIndex == 1) {
          return a.size.compareTo(b.size);
        } else {
          return a.lastUpdated.compareTo(b.lastUpdated);
        }
      }

      return sort;
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
