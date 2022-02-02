part of '../drive_detail_page.dart';

Widget _buildDataTable(BuildContext context, DriveDetailLoadSuccess state) =>
    Scrollbar(
      child: ListView(
        children: [
          DataTable(
            showCheckboxColumn: false,
            columns: _buildTableColumns(context),
            sortColumnIndex: DriveOrder.values.indexOf(state.contentOrderBy),
            sortAscending: state.contentOrderingMode == OrderingMode.asc,
            rows: [
              ...state.folderInView.subfolders.map(
                (folder) => _buildFolderRow(
                  context: context,
                  folder: folder,
                  selected: folder.id == state.maybeSelectedItem?.id,
                  onPressed: () {
                    final bloc = context.read<DriveDetailCubit>();
                    if (folder.id == state.maybeSelectedItem?.id) {
                      bloc.openFolder(path: folder.path);
                    } else {
                      bloc.selectItem(SelectedFolder(folder: folder));
                    }
                  },
                ),
              ),
              ...state.folderInView.files.map(
                (file) => _buildFileRow(
                  context: context,
                  file: file,
                  selected: file.id == state.maybeSelectedItem?.id,
                  onPressed: () async {
                    final bloc = context.read<DriveDetailCubit>();
                    if (file.id == state.maybeSelectedItem?.id) {
                      bloc.toggleSelectedItemDetails();
                    } else {
                      await bloc.selectItem(SelectedFile(file: file));
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
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

String trimName({required String name, required BuildContext context}) {
  const endBuffer = 8;
  final width = MediaQuery.of(context).size.width;
  // No better way to do this. Lerping is too gradual and causes overlap.
  var stringLength = width > 1600
      ? 75
      : width > 1400
          ? 50
          : width > 1200
              ? 35
              : 20;

  // If info sidebar is closed increase the width
  final driveState = context.read<DriveDetailCubit>().state;
  if (driveState is DriveDetailLoadSuccess &&
      !driveState.showSelectedItemDetails) {
    stringLength += 20;
  }
  return name.length > stringLength
      ? name.substring(0, stringLength - endBuffer) +
          ' ... ' +
          name.substring(name.length - endBuffer)
      : name;
}

DataRow _buildFolderRow({
  required BuildContext context,
  required FolderEntry folder,
  bool selected = false,
  required Function onPressed,
}) {
  return DataRow(
    onSelectChanged: (_) => onPressed(),
    selected: selected,
    cells: folder.isGhost
        ? [
            DataCell(
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                        end: 8.0, top: 8.0, bottom: 8.0),
                    child: const Icon(Icons.folder),
                  ),
                  Text(
                    trimName(name: folder.name, context: context),
                  ),
                ],
              ),
            ),
            DataCell(Text('')),
            DataCell(
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  primary: LightColors.kOnLightSurfaceMediumEmphasis,
                  textStyle:
                      TextStyle(color: LightColors.kOnDarkSurfaceHighEmphasis),
                ),
                onPressed: () => showCongestionDependentModalDialog(
                  context,
                  () => promptToReCreateFolder(context, ghostFolder: folder),
                ),
                child: Text('Fix'),
              ),
            ),
          ]
        : [
            DataCell(
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8.0),
                    child: const Icon(Icons.folder),
                  ),
                  Text(
                    trimName(name: folder.name, context: context),
                  ),
                ],
              ),
            ),
            DataCell(Text('-')),
            DataCell(Text('-')),
          ],
  );
}

DataRow _buildFileRow({
  required BuildContext context,
  required FileWithLatestRevisionTransactions file,
  bool selected = false,
  required Function onPressed,
}) {
  return DataRow(
    onSelectChanged: (_) => onPressed(),
    selected: selected,
    cells: [
      DataCell(
        Row(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8.0),
              child: _buildFileIcon(
                fileStatusFromTransactions(file.metadataTx, file.dataTx),
                file.dataContentType,
              ),
            ),
            Text(
              trimName(name: file.name, context: context),
            ),
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
}

Widget _buildFileIcon(String status, String? dataContentType) {
  String tooltipMessage;
  Color indicatorColor;
  Widget icon;

  switch (status) {
    case TransactionStatus.pending:
      tooltipMessage = 'Pending';
      indicatorColor = Colors.orange;
      break;
    case TransactionStatus.confirmed:
      tooltipMessage = 'Confirmed';
      indicatorColor = Colors.green;
      break;
    case TransactionStatus.failed:
      tooltipMessage = 'Failed';
      indicatorColor = Colors.red;
      break;
    default:
      throw ArgumentError();
  }

  final fileType = dataContentType?.split('/').first;
  switch (fileType) {
    case 'image':
      icon = const Icon(Icons.image);
      break;
    case 'video':
      icon = const Icon(Icons.ondemand_video);
      break;
    case 'audio':
      icon = const Icon(Icons.music_note);
      break;
    default:
      icon = const Icon(Icons.insert_drive_file);
  }

  return Tooltip(
    message: tooltipMessage,
    child: Stack(
      children: [
        icon,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: indicatorColor,
              borderRadius: BorderRadius.circular(6),
            ),
            constraints: const BoxConstraints(
              minWidth: 8,
              minHeight: 8,
            ),
          ),
        ),
      ],
    ),
  );
}
