part of '../drive_detail_page.dart';

class DriveDetailDataTableSource extends DataTableSource {
  final List<DriveTableFolder> folders;
  final List<DriveTableFile> files;
  final BuildContext context;
  final bool checkBoxEnabled;
  DriveDetailDataTableSource({
    required this.folders,
    required this.files,
    required this.context,
    required this.checkBoxEnabled,
  });

  @override
  DataRow? getRow(int index) {
    assert(index >= 0);

    if (index >= rowCount) {
      return null;
    }

    if (index < folders.length) {
      final folder = folders[index];
      return _buildFolderRow(
        context: context,
        folder: folder.folder,
        onPressed: folder.onPressed,
        index: index,
        selected: folder.selected,
        checkBoxEnabled: checkBoxEnabled,
      );
    } else {
      final fileIndex = index - folders.length;
      final file = files[fileIndex];
      return _buildFileRow(
        context: context,
        file: file.file,
        onPressed: file.onPressed,
        index: index,
        checkBoxEnabled: checkBoxEnabled,
        selected: file.selected,
      );
    }
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => folders.length + files.length;

  @override
  int get selectedRowCount => 0;
}

class DriveTableFile {
  final FileWithLatestRevisionTransactions file;
  final bool selected;
  final Function onPressed;

  DriveTableFile({
    required this.file,
    required this.selected,
    required this.onPressed,
  });
}

class DriveTableFolder {
  final FolderEntry folder;
  final bool selected;
  final Function onPressed;

  DriveTableFolder({
    required this.folder,
    required this.selected,
    required this.onPressed,
  });
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
      ? '${name.substring(0, stringLength - endBuffer)} ... ${name.substring(name.length - endBuffer)}'
      : name;
}

DataRow _buildFolderRow({
  required BuildContext context,
  required FolderEntry folder,
  bool selected = false,
  required Function onPressed,
  required int index,
  required bool checkBoxEnabled,
}) {
  return DataRow.byIndex(
    onSelectChanged: (_) => onPressed(),
    selected: selected,
    index: index,
    cells: [
      if (checkBoxEnabled)
        DataCell(
          AbsorbPointer(child: Checkbox(value: selected, onChanged: (_) {})),
        )
      else
        const DataCell(SizedBox(width: 32)),
      DataCell(
        Row(
          children: [
            const Padding(
              padding: EdgeInsetsDirectional.only(end: 8.0),
              child: Icon(Icons.folder),
            ),
            Text(
              trimName(name: folder.name, context: context),
            ),
          ],
        ),
      ),
      const DataCell(Text('-')),
      folder.isGhost
          ? DataCell(
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  primary: LightColors.kOnLightSurfaceMediumEmphasis,
                  textStyle: const TextStyle(
                      color: LightColors.kOnDarkSurfaceHighEmphasis),
                ),
                onPressed: () => showCongestionDependentModalDialog(
                  context,
                  () => promptToReCreateFolder(context, ghostFolder: folder),
                ),
                child: Text(appLocalizationsOf(context).fix),
              ),
            )
          : const DataCell(Text('-')),
    ],
  );
}

DataRow _buildFileRow({
  required BuildContext context,
  required FileWithLatestRevisionTransactions file,
  bool selected = false,
  required Function onPressed,
  required int index,
  required bool checkBoxEnabled,
}) {
  return DataRow.byIndex(
    index: index,
    onSelectChanged: (_) => onPressed(),
    selected: selected,
    cells: [
      if (checkBoxEnabled)
        DataCell(
          AbsorbPointer(child: Checkbox(value: selected, onChanged: (_) {})),
        )
      else
        const DataCell(SizedBox(width: 32)),
      DataCell(
        Row(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8.0),
              child: _buildFileIcon(
                fileStatusFromTransactions(file.metadataTx, file.dataTx),
                file.dataContentType,
                appLocalizationsOf(context),
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

Widget _buildFileIcon(
  String status,
  String? dataContentType,
  AppLocalizations localizations,
) {
  String tooltipMessage;
  Color indicatorColor;
  Widget icon;

  switch (status) {
    case TransactionStatus.pending:
      tooltipMessage = localizations.pending;
      indicatorColor = Colors.orange;
      break;
    case TransactionStatus.confirmed:
      tooltipMessage = localizations.confirmed;
      indicatorColor = Colors.green;
      break;
    case TransactionStatus.failed:
      tooltipMessage = localizations.failed;
      indicatorColor = Colors.red;
      break;
    default:
      throw ArgumentError();
  }

  if (dataContentType == ContentType.manifest) {
    icon = const Icon(Icons.account_tree_outlined);
  } else {
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
