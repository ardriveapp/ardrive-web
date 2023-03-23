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
import 'package:ardrive/download/multiple_file_download_modal.dart';
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
              mobile: _mobileView(state, hasSubfolders, hasFiles),
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
                                  content: _buildItem(
                                    appLocalizationsOf(context).renameDrive,
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
                                  appLocalizationsOf(context).shareDrive,
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
                          const SizedBox(width: 16),
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
                      DriveDetailFolderEmptyCard(
                        driveId: state.currentDrive.id,
                        parentFolderId: state.folderInView.folder.id,
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
    );
  }

  Widget _mobileView(
      DriveDetailLoadSuccess state, bool hasSubfolders, bool hasFiles) {
    int index = 0;
    final folders = state.folderInView.subfolders.map(
      (folder) => DriveDataTableItemMapper.fromFolderEntry(
        folder,
        (selected) {
          final bloc = context.read<DriveDetailCubit>();
          bloc.openFolder(path: folder.path);
        },
        index++,
      ),
    );

    final files = state.folderInView.files.map(
      (file) => DriveDataTableItemMapper.toFileDataTableItem(
        file,
        (selected) async {
          final bloc = context.read<DriveDetailCubit>();
          if (file.id == state.maybeSelectedItem()?.id) {
            bloc.toggleSelectedItemDetails();
          } else {
            await bloc.selectItem(SelectedFile(file: file));
          }
        },
        index++,
      ),
    );

    final items = [...folders, ...files];

    return Scrollbar(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Flexible(
                  child: MobileFolderNavigation(
                    driveName: state.currentDrive.name,
                    path: state.folderInView.folder.path,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 16,
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Column(
                      //   crossAxisAlignment: CrossAxisAlignment.start,
                      //   children: [const DriveDetailActionRow()],
                      // ),

                      if (hasSubfolders || hasFiles) ...[
                        Expanded(
                          child: ListView.separated(
                            separatorBuilder: (context, index) =>
                                const SizedBox(
                              height: 5,
                            ),
                            itemCount: folders.length + files.length,
                            itemBuilder: (context, index) {
                              return ArDriveItemListTile(
                                  drive: state.currentDrive,
                                  item: items[index]);
                            },
                          ),
                        ),
                      ] else
                        DriveDetailFolderEmptyCard(
                          promptToAddFiles: state.hasWritePermissions,
                          driveId: state.currentDrive.id,
                          parentFolderId: state.folderInView.folder.id,
                        ),
                    ],
                  ),
                  const PlusButton(),
                ],
              ),
            ),
          ),
        ],
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
}

class ArDriveItemListTile extends StatelessWidget {
  const ArDriveItemListTile({
    super.key,
    required this.item,
    required this.drive,
  });

  final ArDriveDataTableItem item;
  final Drive drive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        item.onPressed(item);
      },
      child: ArDriveCard(
        content: Row(
          children: [
            DriveExplorerItemTileLeading(
              item: item,
            ),
            const SizedBox(
              width: 12,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          style: ArDriveTypography.body
                              .captionRegular()
                              .copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (item is FileDataTableItem) ...[
                        Text(
                          filesize(item.size),
                          style: ArDriveTypography.body.xSmallRegular(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgOnAccent
                                .withOpacity(0.75),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgOnAccent
                                  .withOpacity(0.75),
                            ),
                            height: 3,
                            width: 3,
                          ),
                        )
                      ],
                      Flexible(
                        child: Text(
                          'Last updated: ${yMMdDateFormatter.format(item.lastUpdated)}',
                          overflow: TextOverflow.ellipsis,
                          style: ArDriveTypography.body.xSmallRegular(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgOnAccent
                                .withOpacity(0.75),
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(
              width: 12,
            ),
            DriveExplorerItemTileTrailing(item: item, drive: drive)
          ],
        ),
      ),
    );
  }
}

class MobileFolderNavigation extends StatelessWidget {
  final String path;
  final String driveName;
  const MobileFolderNavigation({
    super.key,
    required this.path,
    required this.driveName,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 45,
      child: Row(
        children: [
          if (path.isNotEmpty)
            IconButton(
              icon: ArDriveIcons.arrowBack(),
              onPressed: () {
                context
                    .read<DriveDetailCubit>()
                    .openFolder(path: getParentFolderPath(path));
              },
            ),
          Expanded(
            child: Padding(
              padding: path.isEmpty
                  ? const EdgeInsets.only(left: 16)
                  : EdgeInsets.zero,
              child: Text(
                _pathToName(path),
                style: ArDriveTypography.body.buttonNormalBold(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _pathToName(String path) {
    if (path.isEmpty) {
      return driveName;
    }

    path += '/';

    return getBasenameFromPath(path);
  }

  String getParentFolderPath(String path) {
    final folders =
        path.split('/'); // Split the path into individual folder names
    folders.removeLast(); // Remove the last folder name
    print(folders.join('/') + '/');
    return folders.join('/');
  }
}

class CustomBottomNavigation extends StatelessWidget {
  const CustomBottomNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 87,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 10,
            offset:
                const Offset(0, -2), // this will add the shadow only on the top
          ),
        ],
        color: ArDriveTheme.of(context).themeData.backgroundColor,
      ),
      width: MediaQuery.of(context).size.width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ArDriveDropdown(
            anchor: const Aligned(
              follower: Alignment.bottomCenter,
              target: Alignment.topCenter,
            ),
            items: [
              ArDriveDropdownItem(
                content: Text(appLocalizationsOf(context).newFolder),
              ),
              ArDriveDropdownItem(
                content: Text(appLocalizationsOf(context).uploadFiles),
              ),
              ArDriveDropdownItem(
                content: Text(appLocalizationsOf(context).uploadFolder),
              ),
              ArDriveDropdownItem(
                content: Text(appLocalizationsOf(context).newDrive),
              ),
              ArDriveDropdownItem(
                content: Text(appLocalizationsOf(context).attachDrive),
              ),
              ArDriveDropdownItem(
                content: Text(appLocalizationsOf(context).createSnapshot),
              ),
            ],
            child: ArDriveFAB(
              child: ArDriveIcons.plus(),
              backgroundColor:
                  ArDriveTheme.of(context).themeData.colors.themeAccentBrand,
            ),
          ),
        ],
      ),
    );
  }
}
