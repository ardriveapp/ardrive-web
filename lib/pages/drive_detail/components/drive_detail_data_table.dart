part of '../drive_detail_page.dart';

Widget _buildDataTable(BuildContext context, DriveDetailLoadSuccess state) {
  return DriveDataTable(
    driveDetailState: state,
    context: context,
  );
}

class DriveDataTable extends StatefulWidget {
  final DriveDetailLoadSuccess driveDetailState;
  final BuildContext context;
  const DriveDataTable({
    Key? key,
    required this.driveDetailState,
    required this.context,
  }) : super(key: key);

  @override
  State<DriveDataTable> createState() => _DriveDataTableState();
}

class _DriveDataTableState extends State<DriveDataTable> {
  final _focusTable = FocusNode();
  var checkboxEnabled = false;
  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _focusTable,
      autofocus: true,
      onKey: (event) async {
        // detect if ctrl + v or cmd + v is pressed
        if (event.isKeyPressed(LogicalKeyboardKey.metaLeft)) {
          if (event is RawKeyDownEvent) {
            setState(() => checkboxEnabled = true);
          }
        } else {
          setState(() => checkboxEnabled = false);
        }
        context.read<DriveDetailCubit>().setMultiSelect(checkboxEnabled);
      },
      child: CustomPaginatedDataTable(
        // The key is used to rerender the data table whenever the folderInView is
        // updated. This includes revisions on the containing files and folders,
        // transaction status updates, renames and moves.
        tableKey:
            ObjectKey([widget.driveDetailState.folderInView, checkboxEnabled]),

        columns: _buildTableColumns(context),
        sortColumnIndex:
            DriveOrder.values.indexOf(widget.driveDetailState.contentOrderBy),
        sortAscending:
            widget.driveDetailState.contentOrderingMode == OrderingMode.asc,
        rowsPerPage: widget.driveDetailState.rowsPerPage,
        availableRowsPerPage: widget.driveDetailState.availableRowsPerPage,
        onRowsPerPageChanged: (value) => setState(
            () => context.read<DriveDetailCubit>().setRowsPerPage(value!)),
        showFirstLastButtons: true,
        showCheckboxColumn: checkboxEnabled,
        source: DriveDetailDataTableSource(
          context: context,
          files: widget.driveDetailState.folderInView.files
              .map(
                (file) => DriveTableFile(
                  file: file,
                  selected: checkboxEnabled
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
                  selected: checkboxEnabled
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
      ),
    );
  }
}

List<DataColumn> _buildTableColumns(BuildContext context) {
  onSort(columnIndex, sortAscending) =>
      context.read<DriveDetailCubit>().sortFolder(
            contentOrderBy: DriveOrder.values[columnIndex],
            contentOrderingMode:
                sortAscending ? OrderingMode.asc : OrderingMode.desc,
          );
  return [
    DataColumn(
        label: Text(
          appLocalizationsOf(context).name,
          overflow: TextOverflow.ellipsis,
        ),
        onSort: onSort),
    DataColumn(
        label: Text(
          appLocalizationsOf(context).fileSize,
          overflow: TextOverflow.ellipsis,
        ),
        onSort: onSort),
    DataColumn(
        label: Text(
          appLocalizationsOf(context).lastUpdated,
          overflow: TextOverflow.ellipsis,
        ),
        onSort: onSort),
  ];
}
