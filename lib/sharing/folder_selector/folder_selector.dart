import 'package:ardrive/models/drive.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/sharing/folder_selector/folder_selector_bloc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class FolderSelector extends StatefulWidget {
  const FolderSelector({super.key, required this.onSelect});

  final Function(String driveId, String folderId) onSelect;

  @override
  State<FolderSelector> createState() => _FolderSelectorState();
}

class _FolderSelectorState extends State<FolderSelector> {
  @override
  void initState() {
    super.initState();
    context.read<FolderSelectorBloc>().add(LoadDrivesEvent());
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FolderSelectorBloc, FolderSelectorState>(
      listener: (context, state) {
        if (state is FolderSelectedState) {
          widget.onSelect(state.folder, state.driveId);
        }
      },
      builder: (context, state) {
        String title;
        String description = '';
        Widget content;
        final colors = ArDriveTheme.of(context).themeData.colors;
        final actions = <ModalAction>[];
        if (state is SelectingDriveState) {
          final publicDrives =
              state.drives.where((drive) => !drive.isPrivate).toList();
          final privateDrives =
              state.drives.where((drive) => drive.isPrivate).toList();
          title = 'Select Drive';
          description = 'Select the drive you want to upload to';
          content = SizedBox(
            width: 200,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (publicDrives.isNotEmpty) ...[
                    Text(
                      'Public Drives',
                      style: ArDriveTypography.body.buttonLargeBold(),
                    ),
                    const Divider(),
                    ListView.builder(
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: publicDrives.length,
                      shrinkWrap: true,
                      itemBuilder: (context, index) {
                        final color = state.selectedDrive == null
                            ? null
                            : state.selectedDrive != null
                                ? publicDrives[index].id ==
                                        state.selectedDrive!.id
                                    ? null
                                    : colors.themeAccentDisabled
                                : null;
                        return ListTile(
                          leading: ArDriveIcons.addDrive(
                            color: color,
                          ),
                          title: Text(
                            state.drives[index].name,
                            style: ArDriveTypography.body
                                .buttonLargeBold(
                                  color: color,
                                )
                                .copyWith(
                                  fontWeight: state.selectedDrive?.id ==
                                          state.drives[index].id
                                      ? FontWeight.w700
                                      : null,
                                ),
                          ),
                          onTap: () {
                            context
                                .read<FolderSelectorBloc>()
                                .add(SelectDriveEvent(state.drives[index]));
                          },
                        );
                      },
                    ),
                  ],
                  if (privateDrives.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Private Drives',
                      style: ArDriveTypography.body.buttonLargeBold(),
                    ),
                    const Divider(),
                    ListView.builder(
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: privateDrives.length,
                      shrinkWrap: true,
                      itemBuilder: (context, index) {
                        final color = state.selectedDrive == null
                            ? null
                            : state.selectedDrive != null
                                ? privateDrives[index].id ==
                                        state.selectedDrive!.id
                                    ? null
                                    : colors.themeAccentDisabled
                                : null;
                        return ListTile(
                          leading: ArDriveIcons.addDrive(
                            color: color,
                          ),
                          title: Text(
                            state.drives[index].name,
                            style: ArDriveTypography.body
                                .buttonLargeBold(
                                  color: color,
                                )
                                .copyWith(
                                  fontWeight: state.selectedDrive?.id ==
                                          state.drives[index].id
                                      ? FontWeight.w700
                                      : null,
                                ),
                          ),
                          onTap: () {
                            context
                                .read<FolderSelectorBloc>()
                                .add(SelectDriveEvent(state.drives[index]));
                          },
                        );
                      },
                    ),
                  ]
                ],
              ),
            ),
          );
          actions.add(
            ModalAction(
              title: 'Cancel',
              action: () {
                Navigator.of(context).pop();
              },
            ),
          );

          actions.add(
            ModalAction(
              isEnable: state.selectedDrive != null,
              title: 'Confirm',
              action: () {
                context
                    .read<FolderSelectorBloc>()
                    .add(ConfirmDriveEvent(state.selectedDrive!));
              },
            ),
          );
        } else if (state is SelectingFolderState) {
          title = 'Select Folder';
          description = 'Select the folder you want to upload to';
          content = ListView.builder(
            itemCount: state.folders.length,
            shrinkWrap: true,
            itemBuilder: (context, index) {
              final color = state.selectedFolder == null
                  ? null
                  : state.selectedFolder != null
                      ? state.folders[index].id == state.selectedFolder!.id
                          ? null
                          : colors.themeAccentDisabled
                      : null;
              return SizedBox(
                width: 200,
                child: ListTile(
                  leading:
                      getIconForContentType('folder', color: color, size: 24),
                  title: Text(
                    state.folders[index].name,
                    style: ArDriveTypography.body
                        .buttonLargeBold(
                          color: color,
                        )
                        .copyWith(
                            fontWeight: state.selectedFolder?.id ==
                                    state.folders[index].id
                                ? FontWeight.w700
                                : null),
                  ),
                  onTap: () {
                    context
                        .read<FolderSelectorBloc>()
                        .add(SelectFolderEvent(state.folders[index]));
                  },
                ),
              );
            },
          );

          actions.addAll([
            ModalAction(
              title: 'Back',
              action: () {
                context.read<FolderSelectorBloc>().add(SelectDriveEvent(
                    context.read<FolderSelectorBloc>().selectedDrive!));
              },
            ),
            ModalAction(
              isEnable: state.selectedFolder != null,
              title: 'Upload',
              action: () {
                context
                    .read<FolderSelectorBloc>()
                    .add(ConfirmFolderEvent(state.selectedFolder!));
                Navigator.of(context).pop();
              },
            ),
          ]);
        } else {
          title = 'Loading';
          content = const Center(child: CircularProgressIndicator());
        }

        return ArDriveStandardModal(
          title: title,
          description: description,
          actions: actions,
          content: SizedBox(
            height: 400,
            width: 200,
            child: content,
          ),
        );
      },
    );
  }
}
