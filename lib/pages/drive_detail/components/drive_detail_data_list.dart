part of '../drive_detail_page.dart';

Widget _buildDataList(BuildContext context, DriveDetailLoadSuccess state) {
  print('building data list');
  List<ArDriveDataTableItem> items = [];
  print(state.folderInView.folder.id);

  // add folders to items mapping to the correct object
  items.addAll(state.folderInView.subfolders.map(
    (folder) => ArDriveDataTableItem(
      onPressed: (selected) {
        print('selected: $selected');
        final bloc = context.read<DriveDetailCubit>();
        if (folder.id == state.maybeSelectedItem()?.id) {
          bloc.openFolder(path: folder.path);
        } else {
          print('selecting folder: ${folder.name}');
          bloc.openFolder(path: folder.path);
        }
      },
      name: folder.name,
      lastUpdated: yMMdDateFormatter.format(folder.lastUpdated),
      type: 'folder',
      contentType: 'folder',
    ),
  ));

  // add files to items mapping to the correct object
  items.addAll(state.folderInView.files.map(
    (file) => ArDriveDataTableItem(
        name: file.name,
        size: filesize(file.size),
        fileStatusFromTransactions: fileStatusFromTransactions(
          file.metadataTx,
          file.dataTx,
        ).toString(),
        type: 'file',
        contentType: file.dataContentType ?? 'octet-stream',
        lastUpdated: yMMdDateFormatter.format(file.lastUpdated),
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

class ArDriveDataTableItem {
  final String name;
  final String size;
  final String lastUpdated;
  final String type;
  final String contentType;
  final String? fileStatusFromTransactions;
  final Function(ArDriveDataTableItem) onPressed;

  ArDriveDataTableItem({
    required this.name,
    this.size = '-',
    this.lastUpdated = '-',
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
      TableColumn('Last updated', 1)
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
        lastUpdated: row.lastUpdated,
        onPressed: () => row.onPressed(row),
      );
    },
    rows: items,
  );
}
