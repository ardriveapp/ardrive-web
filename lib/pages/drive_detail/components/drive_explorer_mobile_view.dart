import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/components/csv_export_dialog.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/drive_share_dialog.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DriveExplorerMobileView extends StatefulWidget {
  const DriveExplorerMobileView({
    super.key,
    required this.state,
    required this.hasSubfolders,
    required this.hasFiles,
  });

  final DriveDetailLoadSuccess state;
  final bool hasSubfolders;
  final bool hasFiles;

  @override
  State<DriveExplorerMobileView> createState() =>
      _DriveExplorerMobileViewState();
}

class _DriveExplorerMobileViewState extends State<DriveExplorerMobileView> {
  @override
  Widget build(BuildContext context) {
    return _mobileView(widget.state, widget.hasSubfolders, widget.hasFiles);
  }

  Widget _mobileView(
      DriveDetailLoadSuccess state, bool hasSubfolders, bool hasFiles) {
    final isOwner = isDriveOwner(
        context.read<ArDriveAuth>(), state.currentDrive.ownerAddress);

    int index = 0;
    final folders = state.folderInView.subfolders.map(
      (folder) => DriveDataTableItemMapper.fromFolderEntry(
        folder,
        (selected) {
          final bloc = context.read<DriveDetailCubit>();
          bloc.openFolder(path: folder.path);
        },
        index++,
        isOwner,
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
            await bloc.selectDataItem(selected);
          }
        },
        index++,
        isOwner,
      ),
    );

    final items = [...folders, ...files];

    return Column(
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
          child: Scrollbar(
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
                                key: ObjectKey([items[index]]),
                                drive: state.currentDrive,
                                item: items[index],
                              );
                            },
                          ),
                        ),
                      ] else
                        Expanded(
                          child: DriveDetailFolderEmptyCard(
                            promptToAddFiles: state.hasWritePermissions,
                            driveId: state.currentDrive.id,
                            parentFolderId: state.folderInView.folder.id,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
        key: key,
        backgroundColor:
            ArDriveTheme.of(context).themeData.tableTheme.cellColor,
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
                                .themeFgDefault
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
                                  .themeFgDefault
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
                                .themeFgDefault
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
          Expanded(
            child: InkWell(
              onTap: () {
                context
                    .read<DriveDetailCubit>()
                    .openFolder(path: getParentFolderPath(path));
              },
              child: Row(
                children: [
                  if (path.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 15,
                      ),
                      child: ArDriveIcons.arrowBack(),
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
            ),
          ),
          BlocBuilder<DriveDetailCubit, DriveDetailState>(
            builder: (context, state) {
              if (state is DriveDetailLoadSuccess) {
                final isOwner = isDriveOwner(context.read<ArDriveAuth>(),
                    state.currentDrive.ownerAddress);

                return ArDriveDropdown(
                  width: 250,
                  anchor: const Aligned(
                    follower: Alignment.topRight,
                    target: Alignment.bottomRight,
                  ),
                  items: [
                    if (isOwner)
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
                        appLocalizationsOf(context).exportDriveContents,
                        ArDriveIcons.download(),
                      ),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8,
                    ),
                    child: ArDriveIcons.dotsVert(size: 16),
                  ),
                );
              }
              return Container();
            },
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
    return folders.join('/');
  }
}
