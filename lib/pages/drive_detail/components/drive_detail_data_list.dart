part of '../drive_detail_page.dart';

Widget _buildDataList(
  BuildContext context,
  DriveDetailLoadSuccess state,
  Widget emptyState,
) {
  return _buildDataListContent(
    context,
    state.currentFolderContents,
    state.folderInView.folder,
    state.currentDrive,
    isMultiselecting: state.multiselect,
    columnVisibility: state.columnVisibility,
    isShowingHiddenFiles: state.isShowingHiddenFiles,
    emptyState: emptyState,
  );
}

abstract class ArDriveDataTableItem extends IndexedItem {
  final String name;
  final int? size;
  final DateTime lastUpdated;
  final DateTime dateCreated;
  final LicenseType? licenseType;
  final String contentType;
  final String? fileStatusFromTransactions;
  final String id;
  final String driveId;
  final String path;
  final bool isOwner;
  final bool isHidden;

  ArDriveDataTableItem({
    required this.id,
    this.size,
    required this.driveId,
    required this.name,
    required this.lastUpdated,
    required this.dateCreated,
    this.licenseType,
    required this.contentType,
    this.fileStatusFromTransactions,
    required this.path,
    required int index,
    required this.isOwner,
    this.isHidden = false,
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
    super.isHidden,
  });

  @override
  List<Object?> get props => [id, name];
}

class FolderDataTableItem extends ArDriveDataTableItem {
  final String? parentFolderId;
  final bool isGhostFolder;

  FolderDataTableItem({
    required super.driveId,
    required String folderId,
    required super.name,
    required super.lastUpdated,
    required super.dateCreated,
    required super.contentType,
    required super.path,
    super.fileStatusFromTransactions,
    super.isHidden,
    required super.index,
    required super.isOwner,
    this.parentFolderId,
    this.isGhostFolder = false,
  }) : super(id: folderId);

  @override
  List<Object> get props => [id, name, isHidden];
}

class FileDataTableItem extends ArDriveDataTableItem {
  final String fileId;
  final String parentFolderId;
  final String dataTxId;
  final String? licenseTxId;
  final String? bundledIn;
  final DateTime lastModifiedDate;
  final NetworkTransaction? metadataTx;
  final NetworkTransaction? dataTx;
  final String? pinnedDataOwnerAddress;

  FileDataTableItem(
      {required super.driveId,
      required super.lastUpdated,
      required super.name,
      required super.size,
      required super.dateCreated,
      required super.contentType,
      required super.path,
      super.isHidden,
      super.fileStatusFromTransactions,
      required super.index,
      required super.isOwner,
      required this.fileId,
      required this.parentFolderId,
      required this.dataTxId,
      required this.lastModifiedDate,
      required this.metadataTx,
      required this.dataTx,
      required this.pinnedDataOwnerAddress,
      super.licenseType,
      this.licenseTxId,
      this.bundledIn})
      : super(id: fileId);

  @override
  List<Object> get props => [fileId, name, isHidden];
}

Widget _buildDataListContent(
  BuildContext context,
  List<ArDriveDataTableItem> items,
  FolderEntry folder,
  Drive drive, {
  required bool isMultiselecting,
  required Map<int, bool> columnVisibility,
  required bool isShowingHiddenFiles,
  required Widget emptyState,
}) {
  final List<ArDriveDataTableItem> filteredItems;

  if (isShowingHiddenFiles) {
    filteredItems = items.toList();
  } else {
    filteredItems = items.where((item) => item.isHidden == false).toList();
  }

  if (filteredItems.isEmpty) {
    return emptyState;
  }

  return LayoutBuilder(builder: (context, constraints) {
    final columns = [
      TableColumn(
        appLocalizationsOf(context).name,
        9,
        index: 0,
        canHide: false,
      ),
      if (constraints.maxWidth > 500)
        TableColumn(
          appLocalizationsOf(context).size,
          3,
          index: 1,
          canHide: false,
        ),
      if (constraints.maxWidth > 640)
        TableColumn(
          appLocalizationsOf(context).lastUpdated,
          3,
          index: 2,
          isVisible: columnVisibility[2] ?? true,
        ),
      if (constraints.maxWidth > 700)
        TableColumn(
          appLocalizationsOf(context).dateCreated,
          3,
          index: 3,
          isVisible: columnVisibility[3] ?? true,
        ),
      if (constraints.maxWidth > 820)
        TableColumn(
          // TODO: Localize
          // appLocalizationsOf(context).licenseType,
          'License',
          2,
          index: 4,
          isVisible: columnVisibility[4] ?? true,
        ),
    ];

    final driveDetailCubitState = context.read<DriveDetailCubit>().state;
    final forceRebuildKey = driveDetailCubitState is DriveDetailLoadSuccess
        ? driveDetailCubitState.forceRebuildKey
        : null;
    return ArDriveDataTable<ArDriveDataTableItem>(
      key: ValueKey(
          '${folder.id}-${forceRebuildKey.toString()}${columns.length}'),
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
      onChangeColumnVisibility: (column) {
        context.read<DriveDetailCubit>().updateTableColumnVisibility(column);
      },
      forceDisableMultiSelect:
          context.read<DriveDetailCubit>().forceDisableMultiselect,
      columns: columns,
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
          license: row.licenseType == null
              ? ''
              : context
                  .read<LicenseService>()
                  .licenseMetaByType(row.licenseType!)
                  .shortName,
          isHidden: row.isHidden,
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
              } else {
                cubit.selectDataItem(row);
              }
            }
          },
        );
      },
      rows: filteredItems,
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
  if (columnIndex == ColumnIndexes.licenseType) {
    final licenseFiles = items.where((e) => e.licenseType != null).toList();

    licenseFiles.sort((a, b) {
      int result = 0;
      result = (a.licenseType ?? LicenseType.unknown)
          .index
          .compareTo((b.licenseType ?? LicenseType.unknown).index);
      return _getResult(result, ascDescSort);
    });

    final noLicenseFiles = items.where((e) => e.licenseType == null).toList();

    noLicenseFiles.sort((a, b) {
      int result = 0;
      result = compareAlphabeticallyAndNatural(a.name, b.name);
      return _getResult(result, ascDescSort);
    });
    items.clear();
    items.addAll(licenseFiles + noLicenseFiles);
    return;
  }

  items.sort((a, b) {
    int result = 0;
    if (columnIndex == ColumnIndexes.name) {
      result = compareAlphabeticallyAndNatural(a.name, b.name);
    } else if (columnIndex == ColumnIndexes.size) {
      result = (a.size ?? 0).compareTo(b.size ?? 0);
    } else if (columnIndex == ColumnIndexes.lastUpdated) {
      result = a.lastUpdated.compareTo(b.lastUpdated);
    } else if (columnIndex == ColumnIndexes.licenseType) {
      result = (a.licenseType ?? LicenseType.unknown)
          .index
          .compareTo((b.licenseType ?? LicenseType.unknown).index);
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
  static const int licenseType = 4;
}

class DriveDataTableItemMapper {
  static FileDataTableItem toFileDataTableItem(
    FileWithLicenseAndLatestRevisionTransactions file,
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
      licenseTxId: file.licenseTxId,
      metadataTx: file.metadataTx,
      dataTx: file.dataTx,
      licenseType: file.license?.toCompanion(true).licenseTypeEnum,
      index: index,
      pinnedDataOwnerAddress: file.pinnedDataOwnerAddress,
      isHidden: file.isHidden,
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
      isHidden: folderEntry.isHidden,
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
      isHidden: false, // TODO: update me when drives can be hidden
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
      licenseTxId: revision.licenseTxId,
      metadataTx: null,
      dataTx: null,
      index: 0,
      pinnedDataOwnerAddress: revision.pinnedDataOwnerAddress,
      isHidden: revision.isHidden,
    );
  }
}
