import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/copy_icon_button.dart';
import 'package:ardrive/components/csv_export_dialog.dart';
import 'package:ardrive/components/drive_detach_dialog.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/ghost_fixer_form.dart';
import 'package:ardrive/components/plus_button.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart' as entities;
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/drive_file_drop_zone.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/compare_alphabetically_and_natural.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/num_to_string_parsers.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:drift/drift.dart' show OrderingMode;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intersperse/intersperse.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:timeago/timeago.dart';

import '../../core/download_service.dart';
import '../../utils/file_zipper.dart';
import 'components/custom_paginated_data_table.dart';

part 'components/drive_detail_actions_row.dart';
part 'components/drive_detail_breadcrumb_row.dart';
part 'components/drive_detail_data_list.dart';
part 'components/drive_detail_data_table.dart';
part 'components/drive_detail_data_table_source.dart';
part 'components/drive_detail_folder_empty_card.dart';
part 'components/fs_entry_preview_widget.dart';
part 'components/fs_entry_side_sheet.dart';

class DriveDetailPage extends StatefulWidget {
  const DriveDetailPage({
    Key? key,
  }) : super(key: key);

  @override
  State<DriveDetailPage> createState() => _DriveDetailPageState();
}

class _DriveDetailPageState extends State<DriveDetailPage> {
  bool checkboxEnabled = false;
  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: BlocBuilder<DriveDetailCubit, DriveDetailState>(
        builder: (context, state) {
          if (state is DriveDetailLoadInProgress) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is DriveDetailLoadSuccess) {
            return ScreenTypeLayout(
              desktop:
                  BlocListener<KeyboardListenerBloc, KeyboardListenerState>(
                listener: (context, keyListenerState) {
                  // Only allow multiselect on user drives and only if logged in
                },
                child: Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ArDriveCard(
                                  backgroundColor: ArDriveTheme.of(context)
                                      .themeData
                                      .tableTheme
                                      .backgroundColor,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  content: Row(
                                    children: [
                                      DriveDetailBreadcrumbRow(
                                        path: state.folderInView.folder.path,
                                        driveName: state.currentDrive.name,
                                      ),
                                      const Spacer(),
                                      if (state.multiselect)
                                        InkWell(
                                          child: ArDriveIcons.move(),
                                          onTap: () {
                                            promptToMove(
                                              context,
                                              driveId: state.currentDrive.id,
                                              selectedItems: context
                                                  .read<DriveDetailCubit>()
                                                  .selectedItems,
                                            );
                                          },
                                        ),
                                      const SizedBox(width: 8),
                                      if (state.multiselect)
                                        InkWell(
                                          child: ArDriveIcons.download(),
                                          onTap: () {
                                            downloadMultipleFiles(context
                                                .read<DriveDetailCubit>()
                                                .selectedItems);
                                          },
                                        ),
                                      const SizedBox(width: 8),
                                      ArDriveDropdown(
                                        width: 250,
                                        anchor: const Aligned(
                                          follower: Alignment.topRight,
                                          target: Alignment.bottomRight,
                                        ),
                                        items: [
                                          ArDriveDropdownItem(
                                            onClick: () {
                                              promptToRenameDrive(
                                                context,
                                                driveId: state.currentDrive.id,
                                                driveName:
                                                    state.currentDrive.name,
                                              );
                                            },
                                            content: _buildItem(
                                              appLocalizationsOf(context)
                                                  .renameDrive,
                                              ArDriveIcons.edit(),
                                            ),
                                          ),
                                          ArDriveDropdownItem(
                                            onClick: () {
                                              promptToShareDrive(
                                                context: context,
                                                drive: state.currentDrive,
                                              );
                                            },
                                            content: _buildItem(
                                              appLocalizationsOf(context)
                                                  .shareDrive,
                                              ArDriveIcons.share(),
                                            ),
                                          ),
                                          ArDriveDropdownItem(
                                            onClick: () {
                                              promptToExportCSVData(
                                                context: context,
                                                driveId: state.currentDrive.id,
                                              );
                                            },
                                            content: _buildItem(
                                              appLocalizationsOf(context)
                                                  .exportDriveContents,
                                              ArDriveIcons.download(),
                                            ),
                                          ),
                                        ],
                                        child: ArDriveIcons.options(),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        child: ArDriveIcons.closeIcon(),
                                        onTap: () {
                                          context.read<ArDriveAuth>().logout();
                                        },
                                      )
                                    ],
                                  ),
                                ),
                                const SizedBox(
                                  height: 30,
                                ),
                                if (state.folderInView.subfolders.isNotEmpty ||
                                    state.folderInView.files.isNotEmpty)
                                  Expanded(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: _buildDataList(
                                            context,
                                            state,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  DriveDetailFolderEmptyCard(
                                    driveId: state.currentDrive.id,
                                    parentFolderId:
                                        state.folderInView.folder.id,
                                    promptToAddFiles: state.hasWritePermissions,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (state.showSelectedItemDetails) ...{
                          const VerticalDivider(width: 1),
                          FsEntrySideSheet(
                            driveId: state.currentDrive.id,
                            drivePrivacy: state.currentDrive.privacy,
                            maybeSelectedItem: state.selectedItems.isNotEmpty
                                ? state.selectedItems.first
                                : null,
                          ),
                        }
                      ],
                    ),
                    if (kIsWeb)
                      DriveFileDropZone(
                        driveId: state.currentDrive.id,
                        folderId: state.folderInView.folder.id,
                      ),
                  ],
                ),
              ),
              mobile: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!state.showSelectedItemDetails)
                    Expanded(
                      child: Scrollbar(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 16,
                          ),
                          child: Stack(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        state.currentDrive.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headline5,
                                      ),
                                      const SizedBox(
                                        height: 16,
                                      ),
                                      const DriveDetailActionRow()
                                    ],
                                  ),
                                  ArDriveCard(
                                    backgroundColor: ArDriveTheme.of(context)
                                        .themeData
                                        .tableTheme
                                        .backgroundColor,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    content: Row(
                                      children: [
                                        DriveDetailBreadcrumbRow(
                                          path: state.folderInView.folder.path,
                                          driveName: state.currentDrive.name,
                                        ),
                                        GestureDetector(
                                          child: ArDriveIcons.closeIcon(),
                                          onTap: () {
                                            context
                                                .read<ArDriveAuth>()
                                                .logout();
                                          },
                                        )
                                      ],
                                    ),
                                  ),
                                  if (state
                                          .folderInView.subfolders.isNotEmpty ||
                                      state.folderInView.files.isNotEmpty) ...[
                                    Expanded(
                                      child: _buildDataList(context, state),
                                    ),
                                  ] else
                                    DriveDetailFolderEmptyCard(
                                      promptToAddFiles:
                                          state.hasWritePermissions,
                                      driveId: state.currentDrive.id,
                                      parentFolderId:
                                          state.folderInView.folder.id,
                                    ),
                                ],
                              ),
                              const PlusButton(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (state.showSelectedItemDetails)
                    Expanded(
                      child: FsEntrySideSheet(
                        driveId: state.currentDrive.id,
                        drivePrivacy: state.currentDrive.privacy,
                        maybeSelectedItem: state.selectedItems.isNotEmpty
                            ? state.selectedItems.first
                            : null,
                      ),
                    ),
                ],
              ),
            );
          } else {
            return const SizedBox();
          }
        },
      ),
    );
  }

  _buildItem(String name, ArDriveIcon icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 41.0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 375,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: ArDriveTypography.body.buttonNormalBold(),
            ),
            icon,
          ],
        ),
      ),
    );
  }

  downloadMultipleFiles(List<ArDriveDataTableItem> items) async {
    final ioFiles = <IOFile>[];

    for (final file in items) {
      final ARFSFileEntity arfsFile = ARFSFactory()
          .getARFSFileFromFileDataItemTable(file as FileDataTableItem);
      final arweave = context.read<ArweaveService>();
      final dataBytes = await DownloadService(arweave).download(arfsFile.txId);

      final ioFile = await IOFile.fromData(
        dataBytes,
        name: file.name,
        lastModifiedDate: file.lastModifiedDate,
      );

      ioFiles.add(ioFile);
    }

    FileZipper(files: ioFiles).downloadZipFile();
  }
}
