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
  @required FileEntry file,
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
                child: _buildFileIcon(file),
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

Icon _buildFileIcon(FileEntry file) {
  final extension = file.dataContentType?.split('/')?.first;
  print(extension);
  switch (extension) {
    case 'image':
      return Icon(Icons.image);
      break;
    case 'video':
      return Icon(Icons.ondemand_video);
      break;
    case 'audio':
      return Icon(Icons.music_note);
      break;
    default:
      return Icon(Icons.insert_drive_file);
  }
}
