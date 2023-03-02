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
      lastUpdated: folder.lastUpdated,
      dateCreated: folder.dateCreated,
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
    sortRows: (list, columnIndex, sort) {
      // Separate folders and files
      List<ArDriveDataTableItem> folders = [];
      List<ArDriveDataTableItem> files = [];
      for (var item in list) {
        if (item.type == 'folder') {
          folders.add(item);
        } else {
          files.add(item);
        }
      }

      // Sort folders alphabetically
      folders.sort((a, b) {
        int result = compareAlphabeticallyAndNatural(a.name, b.name);
        if (sort == TableSort.asc) {
          result *= -1;
        }
        return result;
      });

      // Sort files based on the specified column index
      files.sort((a, b) {
        int result = 0;

        if (columnIndex == 0) {
          result = compareAlphabeticallyAndNatural(a.name, b.name);
        } else if (columnIndex == 1) {
          result = a.size.compareTo(b.size);
        } else {
          result = a.lastUpdated.compareTo(b.lastUpdated);
        }

        if (sort == TableSort.asc) {
          result *= -1;
        }

        return result;
      });

      // Merge folders and files back together, with folders at the top
      List<ArDriveDataTableItem> result = [];
      result.addAll(folders);
      result.addAll(files);
      return result;
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
