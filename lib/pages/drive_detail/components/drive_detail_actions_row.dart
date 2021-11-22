part of '../drive_detail_page.dart';

class DriveDetailActionRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bloc = context.watch<DriveDetailCubit>();

    return BlocBuilder<DriveDetailCubit, DriveDetailState>(
      builder: (context, state) {
        if (state is DriveDetailLoadSuccess) {
          final fsActions = <Widget>[
            if (state.hasWritePermissions && state.selectedItemId == null) ...[
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () {
                  promptToRenameDrive(context, driveId: state.currentDrive.id);
                },
                tooltip: 'Rename Drive',
              ),
            ],
            if (state.selectedItemId == null)
              IconButton(
                icon: const Icon(Icons.table_chart),
                onPressed: () {
                  promptToExportCSVData(
                      context: context, driveId: state.currentDrive.id);
                },
                tooltip: 'Export Drive Contents',
              ),
            // A folder/file is selected.
            if (state.selectedItemId != null) ...{
              if (!state.selectedItemIsFolder) ...{
                IconButton(
                  icon: const Icon(Icons.file_download),
                  onPressed: () => promptToDownloadProfileFile(
                    context: context,
                    driveId: state.currentDrive.id,
                    fileId: state.selectedItemId as String,
                  ),
                  tooltip: 'Download',
                ),
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: 'Share File',
                  onPressed: () => promptToShareFile(
                    context: context,
                    driveId: state.currentDrive.id,
                    fileId: state.selectedItemId as String,
                  ),
                ),
                if (state.currentDrive.isPublic)
                  Link(
                    uri: state.selectedFilePreviewUrl,
                    target: LinkTarget.blank,
                    builder: (context, followLink) => IconButton(
                      icon: const Icon(Icons.open_in_new),
                      onPressed: followLink,
                      tooltip: 'Preview',
                    ),
                  ),
              },
              if (state.hasWritePermissions) ...{
                IconButton(
                  icon: const Icon(Icons.drive_file_rename_outline),
                  onPressed: () {
                    if (state.selectedItemIsFolder) {
                      promptToRenameFolder(context,
                          driveId: state.currentDrive.id,
                          folderId: state.selectedItemId as String);
                    } else {
                      promptToRenameFile(context,
                          driveId: state.currentDrive.id,
                          fileId: state.selectedItemId as String);
                    }
                  },
                  tooltip: 'Rename',
                ),
                IconButton(
                  icon: const Icon(Icons.drive_file_move),
                  onPressed: () {
                    if (state.selectedItemIsFolder) {
                      promptToMoveFolder(context,
                          driveId: state.currentDrive.id,
                          folderId: state.selectedItemId as String);
                    } else {
                      promptToMoveFile(context,
                          driveId: state.currentDrive.id,
                          fileId: state.selectedItemId as String);
                    }
                  },
                  tooltip: 'Move',
                ),
              },
              // Nothing is selected.
            } else ...{
              if (state.currentDrive.isPublic)
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: () => promptToShareDrive(
                    context: context,
                    driveId: state.currentDrive.id,
                  ),
                  tooltip: 'Share Drive',
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
                  tooltip: 'View Only',
                ),
              state.currentDrive.isPrivate
                  ? IconButton(
                      icon: const Icon(Icons.lock),
                      onPressed: () => bloc.toggleSelectedItemDetails(),
                      tooltip: 'Private',
                    )
                  : IconButton(
                      icon: const Icon(Icons.public),
                      onPressed: () => bloc.toggleSelectedItemDetails(),
                      tooltip: 'Public',
                    ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.info),
                onPressed: () => bloc.toggleSelectedItemDetails(),
                tooltip: 'View Info',
              ),
            ],
          );
        }

        return const SizedBox();
      },
    );
  }
}
