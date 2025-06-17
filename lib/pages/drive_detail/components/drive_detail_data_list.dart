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
    state.selectedItem,
    state.currentDrive,
    isMultiselecting: state.multiselect,
    columnVisibility: state.columnVisibility,
    emptyState: emptyState,
    selectedPage: state.selectedPage,
  );
}

Widget _buildDataListContent(
  BuildContext context,
  List<ArDriveDataTableItem> items,
  FolderEntry folder,
  ArDriveDataTableItem? selectedItem,
  Drive drive, {
  required bool isMultiselecting,
  required Map<int, bool> columnVisibility,
  required Widget emptyState,
  int? selectedPage,
}) {
  return LayoutBuilder(builder: (context, constraints) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    final columns = [
      TableColumn(
        appLocalizationsOf(context).name,
        9,
        index: 0,
        canHide: false,
        textStyle: typography.paragraphNormal(
          color: colorTokens.textMid,
          fontWeight: ArFontWeight.semiBold,
        ),
      ),
      // if (constraints.maxWidth > 500)
      TableColumn(
        appLocalizationsOf(context).size,
        3,
        index: 1,
        canHide: false,
        isVisible:
            (constraints.maxWidth > 500 && (columnVisibility[1] ?? true)),
        textStyle: typography.paragraphNormal(
          color: colorTokens.textMid,
          fontWeight: ArFontWeight.semiBold,
        ),
      ),
      // if (constraints.maxWidth > 640)
      TableColumn(
        appLocalizationsOf(context).lastUpdated,
        3,
        index: 2,
        isVisible:
            (constraints.maxWidth > 640 && (columnVisibility[2] ?? true)),
        textStyle: typography.paragraphNormal(
          color: colorTokens.textMid,
          fontWeight: ArFontWeight.semiBold,
        ),
      ),
      // if (constraints.maxWidth > 700)
      TableColumn(
        appLocalizationsOf(context).dateCreated,
        3,
        index: 3,
        isVisible:
            (constraints.maxWidth > 700 && (columnVisibility[3] ?? true)),
        textStyle: typography.paragraphNormal(
          color: colorTokens.textMid,
          fontWeight: ArFontWeight.semiBold,
        ),
      ),
      // if (constraints.maxWidth > 820)
      TableColumn(
        // TODO: Localize
        // appLocalizationsOf(context).licenseType,
        'License',
        2,
        index: 4,
        textStyle: typography.paragraphNormal(
          color: colorTokens.textMid,
          fontWeight: ArFontWeight.semiBold,
        ),
        isVisible:
            (constraints.maxWidth > 820 && (columnVisibility[4] ?? true)),
      ),
    ];

    final driveDetailCubitState = context.read<DriveDetailCubit>().state;
    final forceRebuildKey = driveDetailCubitState is DriveDetailLoadSuccess
        ? driveDetailCubitState.forceRebuildKey
        : null;
    return BlocBuilder<GlobalHideBloc, GlobalHideState>(
      builder: (context, hideState) {
        List<ArDriveDataTableItem> filteredItems = [];

        if (hideState is HiddingItems) {
          filteredItems = items.where((item) => !item.isHidden).toList();
        } else {
          filteredItems = items.toList();
        }

        if (filteredItems.isEmpty) {
          return emptyState;
        }

        return ArDriveDataTable<ArDriveDataTableItem>(
          key: ValueKey(
              '${folder.id}-${forceRebuildKey.toString()}${columns.length}-${hideState.toString()}'),
          initialPage: selectedPage,
          lockMultiSelect: context.read<SyncCubit>().state is SyncInProgress ||
              !context.read<ActivityTracker>().isMultiSelectEnabled,
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
            context
                .read<DriveDetailCubit>()
                .updateTableColumnVisibility(column);
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
                cubit.openFolder(folderId: item.id);
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
            final typography = ArDriveTypographyNew.of(context);
            final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
            return DriveExplorerItemTile(
              colorTokens: colorTokens,
              name: row.name,
              typography: typography,
              size: row.size == null ? '-' : filesize(row.size),
              lastUpdated: row.lastUpdated,
              dateCreated: row.dateCreated,
              dataTableItem: row,
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
                    cubit.openFolder(folderId: row.id);
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
          selectedRow: selectedItem,
        );
      },
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

