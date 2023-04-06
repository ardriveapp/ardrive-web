part of '../drive_detail_page.dart';

Widget _buildDataList(BuildContext context, DriveDetailLoadSuccess state) {
  int index = 0;

  final folders = state.folderInView.subfolders.map(
    (folder) => DriveDataTableItemMapper.fromFolderEntry(
      folder,
      (selected) {
        final bloc = context.read<DriveDetailCubit>();
        bloc.openFolder(path: folder.path);
      },
      index++,
    ),
  );

  final files = state.folderInView.files.map(
    (file) => DriveDataTableItemMapper.toFileDataTableItem(
      file,
      (selected) async {
        final bloc = context.read<DriveDetailCubit>();
        if (file.id == state.maybeSelectedItem()?.id) {
          bloc.toggleSelectedItemDetails();
        } else {
          bloc.selectDataItem(selected);
        }
      },
      index++,
    ),
  );

  return _buildDataListContent(
    context,
    [...folders, ...files],
    state.folderInView.folder,
    state.currentDrive,
    state.multiselect,
  );
}

abstract class ArDriveDataTableItem extends IndexedItem {
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
    required int index,
  }) : super(index);
}

class DriveDataItem extends ArDriveDataTableItem {
  DriveDataItem({
    required super.id,
    required super.driveId,
    required super.name,
    required super.lastUpdated,
    required super.dateCreated,
    super.contentType = 'drive',
    required super.onPressed,
    super.path = '',
    required super.index,
  });

  @override
  List<Object?> get props => [id, name];
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
    required int index,
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
          index: index,
        );

  @override
  List<Object?> get props => [id, name];
}

class FileDataTableItem extends ArDriveDataTableItem {
  final String fileId;
  final String parentFolderId;
  final String dataTxId;
  final String? bundledIn;
  final DateTime lastModifiedDate;
  final NetworkTransaction? metadataTx;
  final NetworkTransaction? dataTx;

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
    required int index,
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
          index: index,
        );

  @override
  List<Object?> get props => [fileId, name];
}

ArDriveDataTable _buildDataListContent(
  BuildContext context,
  List<ArDriveDataTableItem> items,
  FolderEntry folder,
  Drive drive,
  bool isMultiselecting,
) {
  return ArDriveDataTable<ArDriveDataTableItem>(
    lockMultiSelect: context.watch<SyncCubit>().state is SyncInProgress,
    rowsPerPageText: appLocalizationsOf(context).rowsPerPage,
    maxItemsPerPage: 100,
    pageItemsDivisorFactor: 25,
    onSelectedRows: (boxes) {
      final bloc = context.read<DriveDetailCubit>();

      if (boxes.isEmpty) {
        bloc.setMultiSelect(false);
        return;
      }

      final multiSelectedItems = boxes
          .map((e) => e.selectedItems.map((e) => e))
          .expand((e) => e)
          .toList();

      bloc.selectItems(multiSelectedItems);
    },
    onChangeMultiSelecting: (isMultiselecting) {
      context.read<DriveDetailCubit>().setMultiSelect(isMultiselecting);
    },
    forceDisableMultiSelect:
        context.read<DriveDetailCubit>().forceDisableMultiselect,
    columns: [
      TableColumn(appLocalizationsOf(context).name, 2),
      TableColumn(appLocalizationsOf(context).size, 1),
      TableColumn(appLocalizationsOf(context).lastUpdated, 1),
      TableColumn(appLocalizationsOf(context).dateCreated, 1),
    ],
    trailing: (file) => isMultiselecting
        ? const SizedBox.shrink()
        : DriveExplorerItemTileTrailing(
            drive: drive,
            item: file,
          ),
    leading: (file) => DriveExplorerItemTileLeading(
      item: file,
    ),
    onRowTap: (item) => item.onPressed(item),
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
      Function(ArDriveDataTableItem) onPressed,
      int index) {
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
      index: index,
    );
  }

  static FolderDataTableItem fromFolderEntry(
    FolderEntry folderEntry,
    Function(ArDriveDataTableItem) onPressed,
    int index,
  ) {
    return FolderDataTableItem(
      index: index,
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

  static DriveDataItem fromDrive(
    Drive drive,
    Function(ArDriveDataTableItem) onPressed,
    int index,
  ) {
    return DriveDataItem(
      index: index,
      driveId: drive.id,
      name: drive.name,
      lastUpdated: drive.lastUpdated,
      dateCreated: drive.dateCreated,
      contentType: 'drive',
      onPressed: onPressed,
      id: drive.id,
    );
  }

  static FileDataTableItem fromRevision(FileRevision revision) {
    return FileDataTableItem(
      path: '',
      lastModifiedDate: revision.lastModifiedDate,
      name: revision.name,
      size: revision.size,
      lastUpdated: revision.lastModifiedDate,
      dateCreated: revision.dateCreated,
      contentType: revision.dataContentType ?? '',
      fileStatusFromTransactions: null,
      fileId: revision.fileId,
      onPressed: (_) {},
      driveId: revision.driveId,
      parentFolderId: revision.parentFolderId,
      dataTxId: revision.dataTxId,
      bundledIn: revision.bundledIn,
      metadataTx: null,
      dataTx: null,
      index: 0,
    );
  }
}
