part of '../drive_detail_page.dart';

Widget _buildDataTable({
  required BuildContext context,
  required bool checkBoxEnabled,
  required DriveDetailLoadSuccess state,
}) {
  return DriveDataTable(
    driveDetailState: state,
    checkBoxEnabled: checkBoxEnabled,
    context: context,
  );
}

class DriveDataTable extends StatefulWidget {
  final DriveDetailLoadSuccess driveDetailState;
  final bool checkBoxEnabled;
  final BuildContext context;
  const DriveDataTable({
    Key? key,
    required this.driveDetailState,
    required this.checkBoxEnabled,
    required this.context,
  }) : super(key: key);

  @override
  State<DriveDataTable> createState() => _DriveDataTableState();
}

class _DriveDataTableState extends State<DriveDataTable> {
  @override
  Widget build(BuildContext context) {
    return CustomPaginatedDataTable(
      // The key is used to rerender the data table whenever the folderInView is
      // updated. This includes revisions on the containing files and folders,
      // transaction status updates, renames and moves.
      tableKey: ObjectKey(
        [
          widget.driveDetailState.folderInView,
          widget.checkBoxEnabled,
        ],
      ),

      columns: _buildTableColumns(
        context: context,
        checkBoxEnabled: widget.checkBoxEnabled,
        showItemDetails: widget.driveDetailState.showSelectedItemDetails,
      ),
      // +1 to account for checkbox column
      sortColumnIndex:
          DriveOrder.values.indexOf(widget.driveDetailState.contentOrderBy) + 1,
      sortAscending:
          widget.driveDetailState.contentOrderingMode == OrderingMode.asc,
      rowsPerPage: widget.driveDetailState.rowsPerPage,
      availableRowsPerPage: widget.driveDetailState.availableRowsPerPage,
      onRowsPerPageChanged: (value) => setState(
          () => context.read<DriveDetailCubit>().setRowsPerPage(value!)),
      showFirstLastButtons: true,
      showCheckboxColumn: widget.checkBoxEnabled,
      horizontalMargin: 0,
      source: DriveDetailDataTableSource(
        context: context,
        checkBoxEnabled: widget.checkBoxEnabled,
        files: widget.driveDetailState.folderInView.files.map(
          (file) {
            final selected = widget.checkBoxEnabled
                ? widget.driveDetailState.selectedItems
                    .where((item) => item.id == file.id)
                    .isNotEmpty
                : file.id == widget.driveDetailState.maybeSelectedItem()?.id;

            return DriveTableFile(
              file: file,
              selected: selected,
              onPressed: () async {
                final bloc = context.read<DriveDetailCubit>();
                final showDetailsPanel =
                    file.id == widget.driveDetailState.maybeSelectedItem()?.id;

                if (showDetailsPanel) {
                  if (!widget.checkBoxEnabled) {
                    bloc.toggleSelectedItemDetails();
                  } else {
                    bloc.unselectItem(SelectedFile(file: file));
                  }
                } else {
                  await bloc.selectItem(SelectedFile(file: file));
                }
              },
            );
          },
        ).toList(),
        folders: widget.driveDetailState.folderInView.subfolders.map(
          (folder) {
            return DriveTableFolder(
              folder: folder,
              selected: widget.checkBoxEnabled
                  ? widget.driveDetailState.selectedItems
                      .where((item) => item.id == folder.id)
                      .isNotEmpty
                  : widget.driveDetailState.maybeSelectedItem()?.id ==
                      folder.id,
              onPressed: () {
                final bloc = context.read<DriveDetailCubit>();
                final isCurrentlySelected = widget.checkBoxEnabled &&
                    widget.driveDetailState.selectedItems
                        .where((item) => item.id == folder.id)
                        .isNotEmpty;
                if (isCurrentlySelected) {
                  bloc.unselectItem(SelectedFolder(folder: folder));
                  return;
                }
                final openFolder =
                    widget.driveDetailState.maybeSelectedItem()?.id ==
                        folder.id;

                if (openFolder) {
                  bloc.openFolder(path: folder.path);
                } else {
                  bloc.selectItem(SelectedFolder(folder: folder));
                }
              },
            );
          },
        ).toList(),
      ),
    );
  }
}

List<DataColumn> _buildTableColumns({
  required BuildContext context,
  required bool checkBoxEnabled,
  required bool showItemDetails,
}) {
  onSort(DriveOrder column, sortAscending) {
    context.read<DriveDetailCubit>().sortFolder(
          contentOrderBy: column,
          contentOrderingMode:
              sortAscending ? OrderingMode.asc : OrderingMode.desc,
        );
  }

  final double width = MediaQuery.of(context).size.width -
      (showItemDetails ? 2 * kSideDrawerWidth : kSideDrawerWidth) -
      48;

  return [
    const DataColumn(
      label: SizedBox(
        width: 24,
      ),
    ),
    DataColumn(
      label: SizedBox(
        width: width * .4,
        child: Text(
          appLocalizationsOf(context).name,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onSort: (_, ascending) => onSort(DriveOrder.name, ascending),
    ),
    DataColumn(
      label: SizedBox(
        width: width * .2,
        child: Text(
          appLocalizationsOf(context).fileSize,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onSort: (_, ascending) => onSort(DriveOrder.size, ascending),
    ),
    DataColumn(
      label: SizedBox(
        width: width * .2,
        child: Text(
          appLocalizationsOf(context).lastUpdated,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onSort: (_, ascending) => onSort(DriveOrder.lastUpdated, ascending),
    ),
  ];
}
