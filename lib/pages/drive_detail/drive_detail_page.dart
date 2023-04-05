import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/copy_icon_button.dart';
import 'package:ardrive/components/csv_export_dialog.dart';
import 'package:ardrive/components/drive_detach_dialog.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/ghost_fixer_form.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/download/multiple_file_download_modal.dart';
import 'package:ardrive/entities/entities.dart' as entities;
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_mobile_view.dart';
import 'package:ardrive/pages/drive_detail/components/drive_file_drop_zone.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/compare_alphabetically_and_natural.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/num_to_string_parsers.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:drift/drift.dart' show OrderingMode;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intersperse/intersperse.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:timeago/timeago.dart';

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
            final hasSubfolders = state.folderInView.subfolders.isNotEmpty;

            final isDriveOwner = state.currentDrive.ownerAddress ==
                context.read<ArDriveAuth>().currentUser?.walletAddress;

            final hasFiles =
                state.folderInView.files.isNotEmpty && isDriveOwner;

            final canDownloadMultipleFiles = state.multiselect &&
                state.currentDrive.isPublic &&
                !state.hasFoldersSelected;

            return ScreenTypeLayout(
              desktop: _desktopView(
                isDriveOwner: isDriveOwner,
                state: state,
                hasSubfolders: hasSubfolders,
                hasFiles: hasFiles,
                canDownloadMultipleFiles: canDownloadMultipleFiles,
              ),
              mobile: DriveExplorerMobileView(
                state: state,
                hasSubfolders: hasSubfolders,
                hasFiles: hasFiles,
              ),
            );
          } else {
            return const SizedBox();
          }
        },
      ),
    );
  }

  Widget _desktopView({
    required DriveDetailLoadSuccess state,
    required bool hasSubfolders,
    required bool hasFiles,
    required bool isDriveOwner,
    required bool canDownloadMultipleFiles,
  }) {
    return Stack(
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
                          if (state.multiselect && isDriveOwner)
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
                          const SizedBox(width: 16),
                          if (canDownloadMultipleFiles &&
                              context
                                  .read<AppConfig>()
                                  .enableMultipleFileDownload)
                            InkWell(
                              child: ArDriveIcons.download(),
                              onTap: () {
                                final files = context
                                    .read<DriveDetailCubit>()
                                    .selectedItems
                                    .whereType<FileDataTableItem>()
                                    .toList();

                                promptToDownloadMultipleFiles(
                                  context,
                                  items: files,
                                );
                              },
                            ),
                          const SizedBox(width: 16),
                          ArDriveDropdown(
                            width: 250,
                            anchor: const Aligned(
                              follower: Alignment.topRight,
                              target: Alignment.bottomRight,
                            ),
                            items: [
                              if (isDriveOwner)
                                ArDriveDropdownItem(
                                  onClick: () {
                                    promptToRenameDrive(
                                      context,
                                      driveId: state.currentDrive.id,
                                      driveName: state.currentDrive.name,
                                    );
                                  },
                                  content: ArDriveDropdownItemTile(
                                    name:
                                        appLocalizationsOf(context).renameDrive,
                                    icon: ArDriveIcons.edit(),
                                  ),
                                ),
                              ArDriveDropdownItem(
                                onClick: () {
                                  promptToShareDrive(
                                    context: context,
                                    drive: state.currentDrive,
                                  );
                                },
                                content: ArDriveDropdownItemTile(
                                  name: appLocalizationsOf(context).shareDrive,
                                  icon: ArDriveIcons.share(),
                                ),
                              ),
                              ArDriveDropdownItem(
                                onClick: () {
                                  promptToExportCSVData(
                                    context: context,
                                    driveId: state.currentDrive.id,
                                  );
                                },
                                content: ArDriveDropdownItemTile(
                                  name: appLocalizationsOf(context)
                                      .exportDriveContents,
                                  icon: ArDriveIcons.download(),
                                ),
                              ),
                            ],
                            child: ArDriveIcons.options(),
                          ),
                          const SizedBox(width: 16),
                          ProfileCard(
                            walletAddress: context
                                    .read<ArDriveAuth>()
                                    .currentUser
                                    ?.walletAddress ??
                                '',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(
                      height: 30,
                    ),
                    if (hasFiles || hasSubfolders)
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                      Expanded(
                        child: DriveDetailFolderEmptyCard(
                          driveId: state.currentDrive.id,
                          parentFolderId: state.folderInView.folder.id,
                          promptToAddFiles: state.hasWritePermissions,
                        ),
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
    );
  }
}
