part of '../drive_detail_page.dart';

class DriveDetailActionRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bloc = context.watch<DriveDetailCubit>();

    return BlocBuilder<DriveDetailCubit, DriveDetailState>(
      builder: (context, state) {
        if (state is DriveDetailLoadSuccess) {
          final selectedItem = state.maybeSelectedItem;
          final fsActions = <Widget>[
            if (state.hasWritePermissions && selectedItem == null) ...[
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () {
                  promptToRenameDrive(context, driveId: state.currentDrive.id);
                },
                tooltip:
                    context.ofLocalizations().aFileWithSameNameAlreadyExists,
              ),
            ],
            if (selectedItem == null)
              IconButton(
                  icon: const Icon(Icons.table_chart),
                  onPressed: () {
                    promptToExportCSVData(
                        context: context, driveId: state.currentDrive.id);
                  },
                  tooltip: appLocalizationsOf(context).exportDriveContents),
            // A folder/file is selected.
            if (selectedItem != null) ...{
              if (selectedItem is SelectedFile) ...{
                IconButton(
                  icon: const Icon(Icons.file_download),
                  onPressed: () => promptToDownloadProfileFile(
                    context: context,
                    driveId: state.currentDrive.id,
                    fileId: selectedItem.id,
                    dataTxId: selectedItem.item.dataTxId,
                  ),
                  tooltip: appLocalizationsOf(context).download,
                ),
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: appLocalizationsOf(context).shareFile,
                  onPressed: () => promptToShareFile(
                    context: context,
                    driveId: state.currentDrive.id,
                    fileId: selectedItem.id,
                  ),
                ),
                if (state.currentDrive.isPublic)
                  IconButton(
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () =>
                        launch(state.selectedFilePreviewUrl.toString()),
                    tooltip: appLocalizationsOf(context).preview,
                  ),
              },
              if (state.hasWritePermissions) ...{
                IconButton(
                  icon: const Icon(Icons.drive_file_rename_outline),
                  onPressed: () {
                    if (selectedItem is SelectedFolder &&
                        !selectedItem.item.isGhost) {
                      promptToRenameFolder(
                        context,
                        driveId: state.currentDrive.id,
                        folderId: selectedItem.id,
                      );
                    } else {
                      promptToRenameFile(
                        context,
                        driveId: state.currentDrive.id,
                        fileId: selectedItem.id,
                      );
                    }
                  },
                  tooltip: appLocalizationsOf(context).rename,
                ),
                IconButton(
                  icon: const Icon(Icons.drive_file_move),
                  onPressed: () {
                    if (selectedItem is SelectedFolder) {
                      promptToMoveFolder(
                        context,
                        driveId: state.currentDrive.id,
                        folderId: selectedItem.id,
                      );
                    } else {
                      promptToMoveFile(
                        context,
                        driveId: state.currentDrive.id,
                        fileId: selectedItem.id,
                      );
                    }
                  },
                  tooltip: appLocalizationsOf(context).move,
                ),
              },
              // Nothing is selected.
            } else ...{
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () => promptToShareDrive(
                  context: context,
                  drive: state.currentDrive,
                ),
                tooltip: appLocalizationsOf(context).shareDrive,
              ),
            }
          ];

          return Row(
            children: [
              ...fsActions.intersperseOuter(const SizedBox(width: 8)),
              if (fsActions.isNotEmpty)
                const SizedBox(height: 32, child: VerticalDivider()),
              if (!state.hasWritePermissions)
                IconButton(
                  icon: const Icon(Icons.remove_red_eye),
                  onPressed: () => bloc.toggleSelectedItemDetails(),
                  tooltip: appLocalizationsOf(context).viewOnly,
                ),
              state.currentDrive.isPrivate
                  ? IconButton(
                      icon: const Icon(Icons.lock),
                      onPressed: () => bloc.toggleSelectedItemDetails(),
                      tooltip: appLocalizationsOf(context).private,
                    )
                  : IconButton(
                      icon: const Icon(Icons.public),
                      onPressed: () => bloc.toggleSelectedItemDetails(),
                      tooltip: appLocalizationsOf(context).public,
                    ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.info),
                onPressed: () => bloc.toggleSelectedItemDetails(),
                tooltip: appLocalizationsOf(context).viewInfo,
              ),
            ],
          );
        }

        return const SizedBox();
      },
    );
  }
}
