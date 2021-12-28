part of '../drive_detail_page.dart';

Widget _buildDataTable(BuildContext context, DriveDetailLoadSuccess state) =>
    Scrollbar(
      child: SingleChildScrollView(
          key: UniqueKey(),
          child: PaginatedDataTable(
            showCheckboxColumn: false,
            columns: _buildTableColumns(context),
            sortColumnIndex: DriveOrder.values.indexOf(state.contentOrderBy),
            sortAscending: state.contentOrderingMode == OrderingMode.asc,
            rowsPerPage: 25,
            availableRowsPerPage: [
              50,
              75,
              100,
              state.currentFolder.subfolders.length +
                  state.currentFolder.files.length
            ]..sort((a, b) => a.compareTo(b)),
            source: DriveDetailDataTableSource(
              context: context,
              files: state.currentFolder.files
                  .map(
                    (file) => DriveTableFile(
                      file: file,
                      selected: file.id == state.selectedItemId,
                      onPressed: () async {
                        final bloc = context.read<DriveDetailCubit>();
                        if (file.id == state.selectedItemId) {
                          bloc.toggleSelectedItemDetails();
                        } else {
                          await bloc.selectItem(file.id);
                        }
                      },
                    ),
                  )
                  .toList(),
              folders: state.currentFolder.subfolders
                  .map(
                    (folder) => DriveTableFolder(
                      folder: folder,
                      selected: folder.id == state.selectedItemId,
                      onPressed: () {
                        final bloc = context.read<DriveDetailCubit>();
                        if (folder.id == state.selectedItemId) {
                          bloc.openFolder(path: folder.path);
                        } else {
                          bloc.selectItem(
                            folder.id,
                            isFolder: true,
                          );
                        }
                      },
                    ),
                  )
                  .toList(),
            ),
          )),
    );

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
