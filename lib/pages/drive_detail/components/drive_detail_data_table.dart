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
  @override
  Widget build(BuildContext context) {
    return CustomPaginatedDataTable(
      tableKey: ObjectKey(widget.driveDetailState.folderInView),
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
      source: DriveDetailDataTableSource(
        context: context,
        files: widget.driveDetailState.folderInView.files
            .map(
              (file) => DriveTableFile(
                file: file,
                selected:
                    file.id == widget.driveDetailState.maybeSelectedItem?.id,
                onPressed: () async {
                  final bloc = context.read<DriveDetailCubit>();
                  if (file.id ==
                      widget.driveDetailState.maybeSelectedItem?.id) {
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
                selected:
                    folder.id == widget.driveDetailState.maybeSelectedItem?.id,
                onPressed: () {
                  final bloc = context.read<DriveDetailCubit>();
                  if (folder.id ==
                      widget.driveDetailState.maybeSelectedItem?.id) {
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

List<DataColumn> _buildTableColumns(BuildContext context) {
  final onSort = (columnIndex, sortAscending) =>
      context.read<DriveDetailCubit>().sortFolder(
            contentOrderBy: DriveOrder.values[columnIndex],
            contentOrderingMode:
                sortAscending ? OrderingMode.asc : OrderingMode.desc,
          );
  return [
    DataColumn(
        label: Text(
          'Name',
          overflow: TextOverflow.ellipsis,
        ),
        onSort: onSort),
    DataColumn(
        label: Text(
          'File size',
          overflow: TextOverflow.ellipsis,
        ),
        onSort: onSort),
    DataColumn(
        label: Text(
          'Last updated',
          overflow: TextOverflow.ellipsis,
        ),
        onSort: onSort),
  ];
}
