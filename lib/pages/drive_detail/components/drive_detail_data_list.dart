part of '../drive_detail_page.dart';

/// A click on a row: choose it, as Google Drive does.
///
/// It does not open the details panel. It used to, so every click opened a
/// panel the reader then had to close before double-clicking to go anywhere.
/// An open panel follows the selection; More info in the row's menu opens a
/// closed one. Clicking a row that is already chosen does nothing new.
void _selectRow(BuildContext context, ArDriveDataTableItem item) {
  context.read<DriveDetailCubit>().selectDataItem(item, openDetails: false);
}

/// Opening a row: a double-click, a tap on a touch screen, Enter, or on a
/// publication a click. See [DriveDetailCubit.openDataItem].
void _openRow(BuildContext context, ArDriveDataTableItem item) {
  context.read<DriveDetailCubit>().openDataItem(item);
}

/// Whether a sync, or an upload under way, is holding multi-select shut. The
/// list's and the gallery's multi-select are held by the same condition.
bool _multiSelectLocked(BuildContext context, String driveId) =>
    SyncingDriveNotice.locksMultiSelect(
      context.watch<SyncCubit>().state,
      syncingDriveId: context.watch<SyncCubit>().syncingDriveId,
      syncingDriveIds: context.watch<SyncCubit>().syncingDriveIds,
      driveId: driveId,
    ) ||
    !context.watch<ActivityTracker>().isMultiSelectEnabled;

/// The folder shown as a gallery, in the sort the reader gave it in the list.
Widget _buildGallery(
  BuildContext context, {
  required List<ArDriveDataTableItem> items,
  required FolderEntry folder,
  required ArDriveDataTableItem? selectedItem,
  required Drive drive,
  required bool lockMultiSelect,
  ScrollController? scrollController,
}) {
  final cubit = context.read<DriveDetailCubit>();
  final sort = cubit.sortForFolder(folder.id);
  return ExplorerGallery(
    key: ValueKey('gallery-${folder.id}'),
    items: items,
    drive: drive,
    folderId: folder.id,
    selectedItem: selectedItem,
    multiSelected: cubit.selectedItems,
    sortColumn: sort?.column,
    sortOrder: sort?.order,
    lockMultiSelect: lockMultiSelect,
    scrollController: scrollController,
  );
}

/// A folder whose every item is hidden: said, with the way to show them.
Widget _allItemsHidden(BuildContext context) => Center(
      child: SingleChildScrollView(
        child: ArDriveEmptyState(
          key: const Key('allItemsHidden'),
          icon: ArDriveIcons.eyeClosed(size: 32),
          title: appLocalizationsOf(context).allItemsHidden,
          actionLabel: appLocalizationsOf(context).showHiddenItems,
          onAction: () => setShowHiddenItems(context, true),
        ),
      ),
    );

/// How wide the explorer's list will be once the details panel has finished
/// sliding in or out.
///
/// The list is squeezed over the panel's 300 ms slide, so a list that picks
/// its columns from its own width drops them part-way through, or in one frame
/// at the end. A list that takes the narrower of this and its own width
/// decides at the start of an opening slide, and still follows a closing one.
/// The same idea as `ListTargetWidth` on the list pages.
class _ExplorerTargetWidth extends InheritedWidget {
  const _ExplorerTargetWidth({required this.width, required super.child});

  final double width;

  /// [actual] narrowed to the target width, when there is one.
  static double narrowed(BuildContext context, double actual) {
    final target = context
        .dependOnInheritedWidgetOfExactType<_ExplorerTargetWidth>()
        ?.width;
    return target == null ? actual : min(actual, target);
  }

  @override
  bool updateShouldNotify(_ExplorerTargetWidth oldWidget) =>
      width != oldWidget.width;
}

/// A publication root's header as it scrolls with the table: the slivers
/// that go first in the table's scroll, and what to show above `emptyState`
/// when there is no table to scroll it with.
class _CollapsingHeader {
  const _CollapsingHeader({
    required this.slivers,
    required this.extent,
    required this.pinnedInset,
    required this.staticHeader,
  });

  final List<Widget> slivers;
  final CollapsingHeaderExtent extent;
  final double pinnedInset;
  final Widget staticHeader;
}

Widget _buildDataList(
  BuildContext context,
  DriveDetailLoadSuccess state,
  Widget emptyState, {
  _CollapsingHeader? collapsingHeader,
}) {
  return _buildDataListContent(
    context,
    state.currentFolderContents,
    state.folderInView.folder,
    state.selectedItem,
    state.currentDrive,
    isMultiselecting: state.multiselect,
    columnVisibility: state.columnVisibility,
    driveHasLicensedFiles: state.driveHasLicensedFiles,
    viewMode: state.viewMode,
    emptyState: emptyState,
    revealSelectedItem: state.revealSelectedItem,
    rowsPerPage: state.rowsPerPage,
    collapsingHeader: collapsingHeader,
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
  bool driveHasLicensedFiles = false,
  ExplorerViewMode viewMode = ExplorerViewMode.list,
  required Widget emptyState,
  bool revealSelectedItem = false,
  required int rowsPerPage,
  _CollapsingHeader? collapsingHeader,
}) {
  return LayoutBuilder(builder: (context, constraints) {
    final width = _ExplorerTargetWidth.narrowed(context, constraints.maxWidth);
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final l10n = appLocalizationsOf(context);

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
      // if (width > 500)
      TableColumn(
        appLocalizationsOf(context).size,
        3,
        index: 1,
        canHide: false,
        isVisible: (width > 500 && (columnVisibility[1] ?? true)),
        textStyle: typography.paragraphNormal(
          color: colorTokens.textMid,
          fontWeight: ArFontWeight.semiBold,
        ),
      ),
      // if (width > 640)
      TableColumn(
        appLocalizationsOf(context).lastUpdated,
        3,
        index: 2,
        isVisible: (width > 640 && (columnVisibility[2] ?? true)),
        textStyle: typography.paragraphNormal(
          color: colorTokens.textMid,
          fontWeight: ArFontWeight.semiBold,
        ),
      ),
      // if (width > 700)
      TableColumn(
        appLocalizationsOf(context).dateCreated,
        3,
        index: 3,
        isVisible: (width > 700 && (columnVisibility[3] ?? true)),
        textStyle: typography.paragraphNormal(
          color: colorTokens.textMid,
          fontWeight: ArFontWeight.semiBold,
        ),
      ),
      // if (width > 820)
      TableColumn(
        appLocalizationsOf(context).tableColumnLicense,
        2,
        index: DriveDetailCubit.licenseColumnIndex,
        textStyle: typography.paragraphNormal(
          color: colorTokens.textMid,
          fontWeight: ArFontWeight.semiBold,
        ),
        // Hidden by default unless something in the drive is licensed: in
        // most drives it was a column of blanks. The reader's choice wins.
        isVisible: width > 820 &&
            DriveDetailCubit.showsLicenseColumn(
              columnVisibility: columnVisibility,
              driveHasLicensedFiles: driveHasLicensedFiles,
            ),
      ),
      // The three after License, so the saved choices keyed by number keep
      // their meaning. They go before License as the table narrows.
      TableColumn(
        l10n.tableColumnType,
        3,
        index: ColumnIndexes.type,
        textStyle: typography.paragraphNormal(
          color: colorTokens.textMid,
          fontWeight: ArFontWeight.semiBold,
        ),
        isVisible: showsAddedColumn(
          index: ColumnIndexes.type,
          width: width,
          columnVisibility: columnVisibility,
        ),
      ),
      TableColumn(
        l10n.tableColumnTransactionId,
        // The short ID in full and its copy button, without a second cut.
        5,
        index: ColumnIndexes.transactionId,
        textStyle: typography.paragraphNormal(
          color: colorTokens.textMid,
          fontWeight: ArFontWeight.semiBold,
        ),
        isVisible: showsAddedColumn(
          index: ColumnIndexes.transactionId,
          width: width,
          columnVisibility: columnVisibility,
        ),
      ),
      TableColumn(
        l10n.tableColumnStatus,
        3,
        index: ColumnIndexes.status,
        textStyle: typography.paragraphNormal(
          color: colorTokens.textMid,
          fontWeight: ArFontWeight.semiBold,
        ),
        isVisible: showsAddedColumn(
          index: ColumnIndexes.status,
          width: width,
          columnVisibility: columnVisibility,
        ),
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
          // Everything here is hidden: say so, with the way to show it. The
          // columns menu that holds that option belongs to the table, and
          // there is no table to open it from.
          final Widget content =
              items.isNotEmpty ? _allItemsHidden(context) : emptyState;
          if (collapsingHeader == null) return content;
          // The header has no list to scroll with.
          return Column(
            children: [
              collapsingHeader.staticHeader,
              Expanded(child: content),
            ],
          );
        }

        // The gallery has no collapsing header to scroll with, which only a
        // publication's root has: that stays a list.
        if (viewMode == ExplorerViewMode.gallery && collapsingHeader == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SyncingDriveNotice(driveId: folder.driveId),
              Expanded(
                child: _buildGallery(
                  context,
                  items: filteredItems,
                  folder: folder,
                  selectedItem: selectedItem,
                  drive: drive,
                  lockMultiSelect: _multiSelectLocked(context, folder.driveId),
                ),
              ),
            ],
          );
        }

        final table = ArDriveDataTable<ArDriveDataTableItem>(
          leadingSlivers: collapsingHeader?.slivers,
          leadingExtent: collapsingHeader?.extent,
          pinnedInset: collapsingHeader?.pinnedInset ?? 0,
          headerDivider: PublicationMode.isOn,
          countOnOnePage: PublicationMode.isOn,
          key: ValueKey(
              '${folder.id}-${forceRebuildKey.toString()}${columns.length}-${hideState.toString()}'),
          // Back where the reader was in this folder - after a rename or a
          // sync rebuilds the table as much as after leaving and returning -
          // unless an item from elsewhere, such as a search result, is to be
          // shown.
          initialPage:
              context.read<DriveDetailCubit>().pageForFolder(folder.id),
          initialScrollOffset:
              context.read<DriveDetailCubit>().scrollOffsetForFolder(folder.id),
          revealRow: revealSelectedItem ? selectedItem : null,
          onChangePage: (page) =>
              context.read<DriveDetailCubit>().rememberPage(folder.id, page),
          onScrollOffsetSaved: (offset) => context
              .read<DriveDetailCubit>()
              .rememberScrollOffset(folder.id, offset),
          // And in the order the reader picked, for the same reason.
          initialSortColumn:
              context.read<DriveDetailCubit>().sortForFolder(folder.id)?.column,
          initialSortOrder:
              context.read<DriveDetailCubit>().sortForFolder(folder.id)?.order,
          onSortChanged: (column, order) => context
              .read<DriveDetailCubit>()
              .rememberSort(folder.id, column, order),
          rowsPerPage: rowsPerPage,
          rowsPerPageOptions: DriveDetailCubit.rowsPerPageOptions,
          onRowsPerPageChanged: (rowsPerPage) =>
              context.read<DriveDetailCubit>().setRowsPerPage(rowsPerPage),
          pageRangeText: (first, last, total) =>
              appLocalizationsOf(context).tablePageRange(first, last, total),
          previousPageText: appLocalizationsOf(context).tablePreviousPage,
          nextPageText: appLocalizationsOf(context).tableNextPage,
          columnsText: appLocalizationsOf(context).tableColumns,
          // Finder's view menu: whether hidden items show is a choice about
          // how the table looks, so it sits with the columns. It was an eye
          // in the top bar.
          viewOptions: [
            if (hideState.userHasHiddenDrive)
              ViewOption(
                key: const Key('showHiddenItemsOption'),
                label: appLocalizationsOf(context).showHiddenItems,
                checked: hideState is ShowingHiddenItems,
                onChanged: (show) => setShowHiddenItems(context, show),
              ),
          ],
          pageText: (page) => appLocalizationsOf(context).tablePageNumber(page),
          // The sync half of this lock is stated out loud rather than left as
          // a silent no-op - see [SyncingDriveNotice], which is given the
          // same condition so the two cannot drift apart.
          lockMultiSelect: _multiSelectLocked(context, folder.driveId),
          rowsPerPageText: appLocalizationsOf(context).rowsPerPage,
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
          trailingWidth: DriveExplorerItemTileTrailing.widthFor,
          trailing: (file) => isMultiselecting
              ? const SizedBox.shrink()
              : DriveExplorerItemTileTrailing(
                  drive: drive,
                  item: file,
                ),
          leading: (file) => DriveExplorerItemTileLeading(
            item: file,
          ),
          // A click selects and a double-click opens, as in any file manager.
          // Opening used to be a second, separate click on a row already
          // chosen - the gesture that means rename everywhere else - and it
          // made entering a folder slower than in any comparable app. A touch
          // screen still opens on a single tap: the table decides which.
          //
          // A publication's visitors are not managing files, they are
          // browsing a page, and a page opens what is clicked: there a click
          // opens too. Selecting many still works from the checkboxes.
          clickOpens: PublicationMode.isOn,
          onRowTap: (item) => _selectRow(context, item),
          onRowOpen: (item) => _openRow(context, item),
          sortRows: (list, columnIndex, ascDescSort) => sortExplorerRows(
            list,
            columnIndex,
            ascDescSort,
            typeLabel: (item) => driveTableTypeLabel(
              l10n,
              driveTableType(
                contentType: item.contentType,
                name: item.name,
              ),
            ),
          ),
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
              license: row is FileDataTableItem && row.licenseTxId != null
                  ? 'Licensed'
                  : '',
              type: driveTableTypeLabel(
                l10n,
                driveTableType(contentType: row.contentType, name: row.name),
              ),
              transactionId: driveTableTransactionId(row),
              status:
                  driveTableStatusLabel(l10n, row.fileStatusFromTransactions),
              statusValue: row.fileStatusFromTransactions,
              isHidden: row.isHidden,
              onPressed: () {
                // Not reached by the table, which handles its own taps; kept
                // in step so the old open-on-second-click cannot linger here.
                _selectRow(context, row);
              },
            );
          },
          rows: filteredItems,
          selectedRow: selectedItem,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Draws nothing unless a sync is holding multi-select shut.
            SyncingDriveNotice(driveId: folder.driveId),
            Expanded(child: table),
          ],
        );
      },
    );
  });
}
