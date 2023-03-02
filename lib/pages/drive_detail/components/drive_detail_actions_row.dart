part of '../drive_detail_page.dart';

class DriveDetailActionRow extends StatelessWidget {
  const DriveDetailActionRow({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bloc = context.watch<DriveDetailCubit>();
    final profile = context.read<ProfileCubit>().state;

    return BlocBuilder<DriveDetailCubit, DriveDetailState>(
      builder: (context, state) {
        if (state is DriveDetailLoadSuccess) {
          final multiSelectEnabled = state.multiselect;
          final maybeSelectedItem =
              state.selectedItems.isNotEmpty ? state.selectedItems.first : null;
          final isViewingSubfolderWithNothingSelected =
              state.hasWritePermissions &&
                  maybeSelectedItem == null &&
                  state.isViewingRootFolder() &&
                  !state.folderInView.folder.isGhost;
          final fsActions = multiSelectEnabled &&
                  state.maybeSelectedItem() != null
              ? [
                  IconButton(
                    icon: const Icon(Icons.drive_file_move),
                    onPressed: () {
                      if (state.selectedItems.isNotEmpty) {
                        promptToMove(
                          context,
                          driveId: state.currentDrive.id,
                          selectedItems: state.selectedItems,
                        ).then(
                          (_) =>
                              context.read<DriveDetailCubit>().clearSelection(),
                        );
                      }
                    },
                    tooltip: appLocalizationsOf(context).move,
                  ),
                ]
              : <Widget>[
                  if (isViewingSubfolderWithNothingSelected) ...[
                    IconButton(
                      icon: const Icon(Icons.drive_file_rename_outline),
                      onPressed: () {
                        showRenameModal(
                          context,
                          driveId: state.currentDrive.id,
                          folderId: state.folderInView.folder.id,
                        );
                      },
                      tooltip: appLocalizationsOf(context).rename,
                    ),
                    IconButton(
                      icon: const Icon(Icons.drive_file_move),
                      onPressed: () {
                        promptToMove(
                          context,
                          driveId: state.currentDrive.id,
                          selectedItems: [
                            SelectedFolder(folder: state.folderInView.folder)
                          ],
                        );
                      },
                      tooltip: appLocalizationsOf(context).move,
                    ),
                  ] else ...[
                    if (state.hasWritePermissions &&
                        maybeSelectedItem == null) ...[
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () {
                          promptToRenameDrive(context,
                              driveId: state.currentDrive.id);
                        },
                        tooltip: appLocalizationsOf(context).renameDrive,
                      ),
                    ],
                    if (!state.hasWritePermissions &&
                        profile is ProfileLoggedIn) ...[
                      IconButton(
                        icon: const Icon(Icons.eject_outlined),
                        onPressed: () {
                          showDetachDriveDialog(
                            context: context,
                            driveID: state.currentDrive.id,
                            driveName: state.currentDrive.name,
                          );
                        },
                        tooltip: appLocalizationsOf(context).detachDrive,
                      ),
                    ],
                    if (maybeSelectedItem == null)
                      IconButton(
                        icon: const Icon(Icons.table_chart),
                        onPressed: () {
                          promptToExportCSVData(
                              context: context, driveId: state.currentDrive.id);
                        },
                        tooltip:
                            appLocalizationsOf(context).exportDriveContents,
                      ),
                  ],

                  // A folder/file is selected.
                  if (maybeSelectedItem != null) ...{
                    if (maybeSelectedItem is SelectedFile) ...{
                      IconButton(
                        icon: const Icon(Icons.file_download),
                        onPressed: () => promptToDownloadProfileFile(
                          context: context,
                          file: maybeSelectedItem.item,
                        ),
                        tooltip: appLocalizationsOf(context).download,
                      ),
                      IconButton(
                        icon: const Icon(Icons.share),
                        tooltip: appLocalizationsOf(context).shareFile,
                        onPressed: () => promptToShareFile(
                          context: context,
                          driveId: state.currentDrive.id,
                          fileId: maybeSelectedItem.id,
                        ),
                      ),
                      if (state.currentDrive.isPublic)
                        IconButton(
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () {
                            final filePreviewUrl = state.selectedFilePreviewUrl;
                            if (filePreviewUrl != null) {
                              openUrl(url: filePreviewUrl);
                            }
                          },
                          tooltip: appLocalizationsOf(context).preview,
                        ),
                    },
                    if (state.hasWritePermissions) ...{
                      IconButton(
                        icon: const Icon(Icons.drive_file_rename_outline),
                        onPressed: () {
                          if (maybeSelectedItem is SelectedFolder &&
                              !maybeSelectedItem.item.isGhost) {
                            showRenameModal(
                              context,
                              driveId: state.currentDrive.id,
                              folderId: maybeSelectedItem.id,
                              fileId: '',
                            );
                          } else {
                            showRenameModal(
                              context,
                              driveId: state.currentDrive.id,
                              fileId: maybeSelectedItem.id,
                            );
                          }
                        },
                        tooltip: appLocalizationsOf(context).rename,
                      ),
                      IconButton(
                        icon: const Icon(Icons.drive_file_move),
                        onPressed: () {
                          if (state.selectedItems.isNotEmpty) {
                            promptToMove(
                              context,
                              driveId: state.currentDrive.id,
                              selectedItems: state.selectedItems,
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

          return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
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
              ));
        }

        return const SizedBox();
      },
    );
  }
}
