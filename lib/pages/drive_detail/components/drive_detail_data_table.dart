part of '../drive_detail_page.dart';

Widget _buildDataTable(BuildContext context, DriveDetailLoadSuccess state) =>
    DataTable(
      showCheckboxColumn: false,
      columns: _buildTableColumns(context),
      sortColumnIndex: DriveOrder.values.indexOf(state.contentOrderBy),
      sortAscending: state.contentOrderingMode == OrderingMode.asc,
      rows: [
        ...state.currentFolder.subfolders.map(
          (folder) => _buildFolderRow(
            context: context,
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
        ),
        ...state.currentFolder.files.map(
          (file) => _buildFileRow(
            context: context,
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
        ),
      ],
    );

List<DataColumn> _buildTableColumns(BuildContext context) {
  final onSort = (columnIndex, sortAscending) =>
      context.read<DriveDetailCubit>().sortFolder(
            contentOrderBy: DriveOrder.values[columnIndex],
            contentOrderingMode:
                sortAscending ? OrderingMode.asc : OrderingMode.desc,
          );

  return [
    DataColumn(label: Text('Name'), onSort: onSort),
    DataColumn(label: Text('File size'), onSort: onSort),
    DataColumn(label: Text('Last updated'), onSort: onSort),
  ];
}

DataRow _buildFolderRow({
  @required BuildContext context,
  @required FolderEntry folder,
  bool selected = false,
  Function onPressed,
}) =>
    DataRow(
      onSelectChanged: (_) => onPressed(),
      selected: selected,
      cells: [
        DataCell(
          Row(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8.0),
                child: const Icon(Icons.folder),
              ),
              Text(folder.name),
            ],
          ),
        ),
        DataCell(Text('-')),
        DataCell(Text('-')),
      ],
    );

DataRow _buildFileRow({
  @required BuildContext context,
  @required FileWithLatestRevisionTransactions file,
  bool selected = false,
  Function onPressed,
}) =>
    DataRow(
      onSelectChanged: (_) => onPressed(),
      selected: selected,
      cells: [
        DataCell(
          Row(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8.0),
                child: Stack(
                  children: [
                    const Icon(Icons.image),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 12,
                          minHeight: 12,
                        ),
                      ),
                    )
                  ],
                ),
              ),
              Text(file.name),
            ],
          ),
        ),
        DataCell(Text(filesize(file.size))),
        DataCell(
          Text(
            // Show a relative timestamp if the file was updated at most 3 days ago.
            file.lastUpdated.difference(DateTime.now()).inDays > 3
                ? format(file.lastUpdated)
                : yMMdDateFormatter.format(file.lastUpdated),
          ),
        ),
      ],
    );
