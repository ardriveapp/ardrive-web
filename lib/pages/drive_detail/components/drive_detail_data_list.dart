part of '../drive_detail_page.dart';

Widget _buildDataList(
  BuildContext context,
  DriveDetailLoadSuccess state,
) {
  return _buildDataListContent(
    context,
    state.currentFolderContents,
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
  final String id;
  final String driveId;
  final String path;
  final bool isOwner;

  ArDriveDataTableItem({
    required this.id,
    this.size,
    required this.driveId,
    required this.name,
    required this.lastUpdated,
    required this.dateCreated,
    required this.contentType,
    this.fileStatusFromTransactions,
    required this.path,
    required int index,
    required this.isOwner,
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
    super.path = '',
    required super.index,
    required super.isOwner,
  });

  @override
  List<Object?> get props => [id, name];
}

class FolderDataTableItem extends ArDriveDataTableItem {
  final String? parentFolderId;
  final bool isGhostFolder;

  FolderDataTableItem({
    required String driveId,
    required String folderId,
    required String name,
    required DateTime lastUpdated,
    required DateTime dateCreated,
    required String contentType,
    required String path,
    String? fileStatusFromTransactions,
    this.parentFolderId,
    this.isGhostFolder = false,
    required int index,
    required bool isOwner,
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
          index: index,
          isOwner: isOwner,
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
  final String? pinnedDataOwnerAddress;

  FileDataTableItem({
    required this.fileId,
    required String driveId,
    required this.parentFolderId,
    required this.dataTxId,
    required DateTime lastUpdated,
    required this.lastModifiedDate,
    required this.metadataTx,
    required this.dataTx,
    required this.pinnedDataOwnerAddress,
    required String name,
    required int size,
    required DateTime dateCreated,
    required String contentType,
    required String path,
    String? fileStatusFromTransactions,
    this.bundledIn,
    required int index,
    required bool isOwner,
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
          index: index,
          isOwner: isOwner,
        );

  @override
  List<Object?> get props => [fileId, name];
}

Widget _buildDataListContent(
  BuildContext context,
  List<ArDriveDataTableItem> items,
  FolderEntry folder,
  Drive drive,
  bool isMultiselecting,
) {
  return LayoutBuilder(builder: (context, constraints) {
    final driveDetailCubitState = context.read<DriveDetailCubit>().state;
    final equtableBust = driveDetailCubitState is DriveDetailLoadSuccess
        ? driveDetailCubitState.equatableBust
        : null;
    return ArDriveDataTable<ArDriveDataTableItem>(
      key: ValueKey(folder.id + equtableBust.toString()),
      lockMultiSelect: context.watch<SyncCubit>().state is SyncInProgress ||
          !context.watch<ActivityTracker>().isMultiSelectEnabled,
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
        TableColumn(appLocalizationsOf(context).name, 3),
        if (constraints.maxWidth > 500)
          TableColumn(appLocalizationsOf(context).size, 1),
        if (constraints.maxWidth > 640)
          TableColumn(appLocalizationsOf(context).lastUpdated, 1),
        if (constraints.maxWidth > 700)
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
      onRowTap: (item) {
        final cubit = context.read<DriveDetailCubit>();
        if (item is FolderDataTableItem) {
          if (item.id == cubit.selectedItem?.id) {
            cubit.openFolder(path: item.path);
          } else {
            cubit.selectDataItem(item);
          }
        } else if (item is FileDataTableItem) {
          if (item.id == cubit.selectedItem?.id) {
            cubit.toggleSelectedItemDetails();
            return;
          }

          cubit.selectDataItem(item);
        }
      },
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
          onPressed: () {
            final cubit = context.read<DriveDetailCubit>();
            if (row is FolderDataTableItem) {
              if (row.id == cubit.selectedItem?.id) {
                cubit.openFolder(path: folder.path);
              } else {
                cubit.selectDataItem(row);
              }
            } else if (row is FileDataTableItem) {
              if (row.id == cubit.selectedItem?.id) {
                cubit.toggleSelectedItemDetails();
                return;
              }
              cubit.selectDataItem(row);
            }
          },
        );
      },
      rows: items,
      selectedRow: context.watch<DriveDetailCubit>().selectedItem,
    );
  });
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
    int index,
    bool isOwner,
  ) {
    return FileDataTableItem(
      isOwner: isOwner,
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
      driveId: file.driveId,
      parentFolderId: file.parentFolderId,
      dataTxId: file.dataTxId,
      bundledIn: file.bundledIn,
      metadataTx: file.metadataTx,
      dataTx: file.dataTx,
      index: index,
      pinnedDataOwnerAddress: file.pinnedDataOwnerAddress,
    );
  }

  static FolderDataTableItem fromFolderEntry(
    FolderEntry folderEntry,
    int index,
    bool isOwner,
  ) {
    return FolderDataTableItem(
      isOwner: isOwner,
      isGhostFolder: folderEntry.isGhost,
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
    );
  }

  static DriveDataItem fromDrive(
    Drive drive,
    Function(ArDriveDataTableItem) onPressed,
    int index,
    bool isOwner,
  ) {
    return DriveDataItem(
      isOwner: isOwner,
      index: index,
      driveId: drive.id,
      name: drive.name,
      lastUpdated: drive.lastUpdated,
      dateCreated: drive.dateCreated,
      contentType: 'drive',
      id: drive.id,
    );
  }

  static FileDataTableItem fromRevision(FileRevision revision, bool isOwner) {
    return FileDataTableItem(
      isOwner: isOwner,
      path: '',
      lastModifiedDate: revision.lastModifiedDate,
      name: revision.name,
      size: revision.size,
      lastUpdated: revision.lastModifiedDate,
      dateCreated: revision.dateCreated,
      contentType: revision.dataContentType ?? '',
      fileStatusFromTransactions: null,
      fileId: revision.fileId,
      driveId: revision.driveId,
      parentFolderId: revision.parentFolderId,
      dataTxId: revision.dataTxId,
      bundledIn: revision.bundledIn,
      metadataTx: null,
      dataTx: null,
      index: 0,
      pinnedDataOwnerAddress: revision.pinnedDataOwnerAddress,
    );
  }
}
