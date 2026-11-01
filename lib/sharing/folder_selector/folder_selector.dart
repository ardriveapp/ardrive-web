import 'package:ardrive/models/drive.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/sharing/folder_selector/folder_selector_bloc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class FolderSelector extends StatefulWidget {
  const FolderSelector({super.key, required this.onSelect, this.dispose});

  final Function? dispose;

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
  dispose() {
    widget.dispose?.call();
    super.dispose();
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
        final colors = ArDriveTheme.of(context).themeData.colorTokens;
        final typography = ArDriveTypographyNew.of(context);
        // A row's label: bold when it's the one chosen.
        TextStyle rowStyle(Color? color, {bool chosen = false}) =>
            typography.paragraphLarge(
              color: color,
              fontWeight: chosen ? ArFontWeight.bold : ArFontWeight.semiBold,
            );
        final actions = <ModalAction>[];
        if (state is SelectingDriveState) {
          final publicDrives =
              state.drives.where((drive) => !drive.isPrivate).toList();
          final privateDrives =
              state.drives.where((drive) => drive.isPrivate).toList();
          title = 'Select drive';
          description = 'Select the drive you want to upload to';
          content = SizedBox(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (publicDrives.isNotEmpty) ...[
                    Text(
                      'Public drives',
                      style: rowStyle(colors.textHigh),
                    ),
                    const Divider(),
                    ListView.builder(
                      padding: EdgeInsets.zero,
                      physics: const ScrollPhysics(),
                      itemCount: publicDrives.length,
                      shrinkWrap: true,
                      itemBuilder: (context, index) {
                        final publicDrive = publicDrives[index];
                        final color = state.selectedDrive == null
                            ? colors.textHigh
                            : state.selectedDrive != null
                                ? publicDrive.id == state.selectedDrive!.id
                                    ? colors.textHigh
                                    : colors.textLow
                                : null;
                        return ListTile(
                          leading: ArDriveIcons.drive(
                            color: color,
                          ),
                          title: Text(
                            publicDrive.name,
                            style: rowStyle(
                              color,
                              chosen: state.selectedDrive?.id == publicDrive.id,
                            ),
                          ),
                          onTap: () {
                            context
                                .read<FolderSelectorBloc>()
                                .add(SelectDriveEvent(publicDrive));
                          },
                        );
                      },
                    ),
                  ],
                  if (privateDrives.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Private drives', style: rowStyle(colors.textHigh)),
                    const Divider(),
                    ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: privateDrives.length,
                      shrinkWrap: true,
                      itemBuilder: (context, index) {
                        final privateDrive = privateDrives[index];
                        final color = state.selectedDrive == null
                            ? colors.textHigh
                            : state.selectedDrive != null
                                ? privateDrive.id == state.selectedDrive!.id
                                    ? colors.textHigh
                                    : colors.textLow
                                : null;
                        return ListTile(
                          leading: ArDriveIcons.drive(
                            color: color,
                          ),
                          title: Text(
                            privateDrive.name,
                            style: rowStyle(
                              color,
                              chosen:
                                  state.selectedDrive?.id == privateDrive.id,
                            ),
                          ),
                          onTap: () {
                            context
                                .read<FolderSelectorBloc>()
                                .add(SelectDriveEvent(privateDrive));
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
            ModalAction.dismiss(
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
          title = 'Select folder';
          description = 'Select the folder you want to upload to';
          content = SizedBox(
            height: 400,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (state.selectedFolder != null) ...[
                    SizedBox(
                      width: 200,
                      height: 48,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (state.isRootFolder)
                            Flexible(
                              child: ListTile(
                                leading:
                                    getIconForContentType('folder', size: 24),
                                title: Text(
                                  'Root folder',
                                  style:
                                      rowStyle(colors.textHigh, chosen: true),
                                ),
                              ),
                            ),
                          if (state.parentFolder != null && !state.isRootFolder)
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 4.0, right: 4),
                              child: SizedBox(
                                width: 24,
                                child: ArDriveIconButton(
                                  icon: ArDriveIcons.arrowLeft(),
                                  onPressed: () {
                                    context.read<FolderSelectorBloc>().add(
                                        SelectFolderEvent(
                                            folder: state.parentFolder!));
                                  },
                                ),
                              ),
                            ),
                          if (!state.isRootFolder)
                            Flexible(
                              child: ListTile(
                                leading:
                                    getIconForContentType('folder', size: 24),
                                title: Text(
                                  state.selectedFolder!.name,
                                  style:
                                      rowStyle(colors.textHigh, chosen: true),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  ListView.builder(
                    padding: EdgeInsets.only(
                        left: state.selectedFolder == null
                            ? 0
                            : state.parentFolder != null
                                ? 48
                                : 20),
                    itemCount: state.folders.length,
                    shrinkWrap: true,
                    physics: const ScrollPhysics(),
                    itemBuilder: (context, index) {
                      final color = state.selectedFolder == null
                          ? colors.textMid
                          : state.selectedFolder != null
                              ? state.folders[index].id ==
                                      state.selectedFolder!.id
                                  ? null
                                  : colors.textLow
                              : null;
                      return SizedBox(
                        width: 200,
                        child: ListTile(
                          leading: getIconForContentType('folder',
                              color: color, size: 24),
                          title: Text(
                            state.folders[index].name,
                            style: rowStyle(
                              color,
                              chosen: state.selectedFolder?.id ==
                                  state.folders[index].id,
                            ),
                          ),
                          onTap: () {
                            context.read<FolderSelectorBloc>().add(
                                SelectFolderEvent(
                                    folder: state.folders[index]));
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );

          actions.addAll([
            ModalAction.dismiss(
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
          content = const Center(
            child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
          );
        }

        return ArDriveStandardModalNew(
          title: title,
          description: description.isEmpty ? null : description,
          actions: actions,
          content: SizedBox(
            height: 400,
            child: content,
          ),
        );
      },
    );
  }
}
