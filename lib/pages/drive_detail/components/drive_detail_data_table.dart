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
      sortColumnIndex:
          DriveOrder.values.indexOf(widget.driveDetailState.contentOrderBy),
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
        files: widget.driveDetailState.folderInView.files
            .map(
              (file) => DriveTableFile(
                file: file,
                selected: widget.checkBoxEnabled
                    ? widget.driveDetailState.selectedItems
                        .where((item) => item.id == file.id)
                        .isNotEmpty
                    : widget.driveDetailState.selectedItems.isNotEmpty &&
                        file.id ==
                            widget.driveDetailState.selectedItems.first.id,
                onPressed: () async {
                  final bloc = context.read<DriveDetailCubit>();
                  if (widget.driveDetailState.selectedItems.isNotEmpty &&
                      file.id ==
                          widget.driveDetailState.selectedItems.first.id) {
                    bloc.toggleSelectedItemDetails();
                  } else {
                    await bloc.selectItem(SelectedFile(file: file));
                  }
                },
              ),
            )
            .toList(),
        folders: widget.driveDetailState.folderInView.subfolders
            .map(
              (folder) => DriveTableFolder(
                folder: folder,
                selected: widget.checkBoxEnabled
                    ? widget.driveDetailState.selectedItems
                        .where((item) => item.id == folder.id)
                        .isNotEmpty
                    : widget.driveDetailState.selectedItems.isNotEmpty &&
                        folder.id ==
                            widget.driveDetailState.selectedItems.first.id,
                onPressed: () {
                  final bloc = context.read<DriveDetailCubit>();
                  if (widget.driveDetailState.selectedItems.isNotEmpty &&
                      folder.id ==
                          widget.driveDetailState.selectedItems.first.id) {
                    bloc.openFolder(path: folder.path);
                  } else {
                    bloc.selectItem(SelectedFolder(folder: folder));
                  }
                },
              ),
            )
            .toList(),
      ),
    );
  }
}

List<DataColumn> _buildTableColumns({
  required BuildContext context,
  required bool checkBoxEnabled,
  required bool showItemDetails,
}) {
  onSort(columnIndex, sortAscending) {
    context.read<DriveDetailCubit>().sortFolder(
          contentOrderBy: DriveOrder.values[columnIndex],
          contentOrderingMode:
              sortAscending ? OrderingMode.asc : OrderingMode.desc,
        );
  }

  const defaultDrawerWidth = 300;
  final double width = MediaQuery.of(context).size.width -
      (showItemDetails ? 2 * defaultDrawerWidth : defaultDrawerWidth);

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
      onSort: onSort,
    ),
    DataColumn(
      label: SizedBox(
        width: width * .2,
        child: Text(
          appLocalizationsOf(context).fileSize,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onSort: onSort,
    ),
    DataColumn(
      label: SizedBox(
        width: width * .2,
        child: Text(
          appLocalizationsOf(context).lastUpdated,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onSort: onSort,
    ),
  ];
}
