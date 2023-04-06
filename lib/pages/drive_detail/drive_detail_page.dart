import 'package:ardrive/app_shell.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/components/app_bottom_bar.dart';
import 'package:ardrive/components/app_top_bar.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/create_snapshot_dialog.dart';
import 'package:ardrive/components/csv_export_dialog.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/components/drive_detach_dialog.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/ghost_fixer_form.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/download/multiple_file_download_modal.dart';
import 'package:ardrive/entities/entities.dart' as entities;
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/drive_file_drop_zone.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/compare_alphabetically_and_natural.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intersperse/intersperse.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:timeago/timeago.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

part 'components/drive_detail_actions_row.dart';
part 'components/drive_detail_breadcrumb_row.dart';
part 'components/drive_detail_data_list.dart';
part 'components/drive_detail_data_table_source.dart';
part 'components/drive_detail_folder_empty_card.dart';
part 'components/fs_entry_preview_widget.dart';

class DriveDetailPage extends StatefulWidget {
  const DriveDetailPage({
    Key? key,
  }) : super(key: key);

  @override
  State<DriveDetailPage> createState() => _DriveDetailPageState();
}

class _DriveDetailPageState extends State<DriveDetailPage> {
  bool checkboxEnabled = false;
  final _scrollController = ScrollController();

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
              mobile: Scaffold(
                drawer: const AppSideBar(),
                appBar: (state.showSelectedItemDetails &&
                        context.read<DriveDetailCubit>().selectedItem != null)
                    ? MobileAppBar(
                        leading: IconButton(
                          icon: ArDriveIcons.arrowBack(),
                          onPressed: () {
                            context
                                .read<DriveDetailCubit>()
                                .toggleSelectedItemDetails();
                          },
                        ),
                      )
                    : null,
                body: _mobileView(
                  state,
                  hasSubfolders,
                  hasFiles,
                ),
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
    return Column(
      children: [
        const AppTopBar(),
        Expanded(
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 24, 0),
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
                                          name: appLocalizationsOf(context)
                                              .renameDrive,
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
                                        name: appLocalizationsOf(context)
                                            .shareDrive,
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
                                    ArDriveDropdownItem(
                                      onClick: () {
                                        final bloc =
                                            context.read<DriveDetailCubit>();

                                        bloc.selectDataItem(
                                          DriveDataTableItemMapper.fromDrive(
                                            state.currentDrive,
                                            (_) => null,
                                            0,
                                          ),
                                        );
                                      },
                                      content: _buildItem(
                                        appLocalizationsOf(context).moreInfo,
                                        ArDriveIcons.info(),
                                      ),
                                    )
                                  ],
                                  child: ArDriveIcons.options(),
                                ),
                                // const SizedBox(width: 16),
                                // ProfileCard(
                                //   walletAddress: context
                                //           .read<ArDriveAuth>()
                                //           .currentUser
                                //           ?.walletAddress ??
                                //       '',
                                // ),
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
                  AnimatedSize(
                      curve: Curves.easeInOut,
                      duration: const Duration(milliseconds: 300),
                      child: Align(
                        alignment: Alignment.center,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 120),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth:
                                    _getMaxWidthForDetailsPanel(state, context),
                                minWidth:
                                    _getMinWidthForDetailsPanel(state, context),
                                maxHeight:
                                    MediaQuery.of(context).size.height - 120),
                            child: state.showSelectedItemDetails &&
                                    context
                                            .read<DriveDetailCubit>()
                                            .selectedItem !=
                                        null
                                ? DetailsPanel(
                                    isSharePage: false,
                                    drivePrivacy: state.currentDrive.privacy,
                                    maybeSelectedItem:
                                        state.maybeSelectedItem(),
                                    item: context
                                        .read<DriveDetailCubit>()
                                        .selectedItem!,
                                  )
                                : const SizedBox(),
                          ),
                        ),
                      ))
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
      ],
    );
  }

  double _getMaxWidthForDetailsPanel(state, BuildContext context) {
    if (state.showSelectedItemDetails &&
        context.read<DriveDetailCubit>().selectedItem != null) {
      if (MediaQuery.of(context).size.width * 0.25 < 375) {
        return 375;
      }
      return MediaQuery.of(context).size.width * 0.25;
    }
    return 0;
  }

  double _getMinWidthForDetailsPanel(state, BuildContext context) {
    if (state.showSelectedItemDetails &&
        context.read<DriveDetailCubit>().selectedItem != null) {
      return 375;
    }
    return 0;
  }

  Widget _mobileView(
      DriveDetailLoadSuccess state, bool hasSubfolders, bool hasFiles) {
    if (state.showSelectedItemDetails &&
        context.read<DriveDetailCubit>().selectedItem != null) {
      return Material(
        child: WillPopScope(
          onWillPop: () async {
            context.read<DriveDetailCubit>().toggleSelectedItemDetails();
            return false;
          },
          child: DetailsPanel(
            isSharePage: false,
            drivePrivacy: state.currentDrive.privacy,
            maybeSelectedItem: state.maybeSelectedItem(),
            item: context.read<DriveDetailCubit>().selectedItem!,
          ),
        ),
      );
    }

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
            await bloc.selectDataItem(selected);
          }
        },
        index++,
      ),
    );

    final items = [...folders, ...files];

    return Scaffold(
      drawer: const AppSideBar(),
      appBar: MobileAppBar(
        leading: (state.showSelectedItemDetails &&
                context.read<DriveDetailCubit>().selectedItem != null)
            ? IconButton(
                icon: ArDriveIcons.arrowBack(),
                onPressed: () {
                  context.read<DriveDetailCubit>().toggleSelectedItemDetails();
                },
              )
            : null,
      ),
      bottomNavigationBar: BlocBuilder<DriveDetailCubit, DriveDetailState>(
        builder: (context, state) {
          if (state is! DriveDetailLoadSuccess) {
            return Container();
          }

          return ResizableComponent(
            scrollController: _scrollController,
            child: CustomBottomNavigation(
              currentFolder: state.folderInView,
              drive: (state).currentDrive,
            ),
          );
        },
      ),
      body: _mobileViewContent(
        state,
        hasSubfolders,
        hasFiles,
        items,
      ),
    );
  }

  Widget _mobileViewContent(DriveDetailLoadSuccess state, bool hasSubfolders,
      bool hasFiles, List<ArDriveDataTableItem> items) {
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
                        // Expanded(
                        //     child: _buildGridView(
                        //   state,
                        //   hasSubfolders,
                        //   hasFiles,
                        //   items,
                        // )
                        // ),
                        Expanded(
                          child: ListView.separated(
                            controller: _scrollController,
                            separatorBuilder: (context, index) =>
                                const SizedBox(
                              height: 5,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              return ArDriveItemListTile(
                                  key: ObjectKey([items[index]]),
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
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGridView(DriveDetailLoadSuccess state, bool hasSubfolders,
      bool hasFiles, List<ArDriveDataTableItem> items) {
    return GridView.builder(
      controller: _scrollController,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final file = items[index];
        return ArDriveGridItem(
          item: file,
          drive: state.currentDrive,
        );
      },
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
                final isDriveOwner = state.currentDrive.ownerAddress ==
                    context.read<ArDriveAuth>().currentUser?.walletAddress;
                return ArDriveDropdown(
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
                    child: ArDriveIcons.options(),
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

class CustomBottomNavigation extends StatelessWidget {
  const CustomBottomNavigation({
    super.key,
    required this.drive,
    required this.currentFolder,
  });

  final Drive drive;
  final FolderWithContents? currentFolder;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = ArDriveTheme.of(context).themeData.backgroundColor;
    return SafeArea(
      bottom: true,
      child: Container(
        height: 87,
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: ArDriveTheme.of(context)
                  .themeData
                  .colors
                  .themeFgDefault
                  .withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
            BoxShadow(color: backgroundColor, offset: const Offset(0, 2)),
            BoxShadow(color: backgroundColor, offset: const Offset(-0, 8)),
          ],
          color: ArDriveTheme.of(context).themeData.backgroundColor,
        ),
        width: MediaQuery.of(context).size.width,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ArDriveDropdown(
              width: MediaQuery.of(context).size.width * 0.6,
              anchor: const Aligned(
                follower: Alignment.bottomCenter,
                target: Alignment.topCenter,
              ),
              items: [
                ArDriveDropdownItem(
                  onClick: () {
                    promptToCreateDrive(context);
                  },
                  content: _buildItem(
                    ArDriveIcons.drive(size: 24),
                    appLocalizationsOf(context).newDrive,
                  ),
                ),
                ArDriveDropdownItem(
                  onClick: () => attachDrive(context: context),
                  content: _buildItem(
                    ArDriveIcons.drive(size: 24),
                    appLocalizationsOf(context).attachDrive,
                  ),
                ),
                ArDriveDropdownItem(
                  onClick: () => promptToCreateFolder(
                    context,
                    driveId: drive.id,
                    parentFolderId: currentFolder!.folder.id,
                  ),
                  content: _buildItem(
                    ArDriveIcons.folderAdd(size: 24),
                    appLocalizationsOf(context).newFolder,
                  ),
                ),
                ArDriveDropdownItem(
                  onClick: () => promptToUpload(
                    context,
                    driveId: drive.id,
                    parentFolderId: currentFolder!.folder.id,
                    isFolderUpload: true,
                  ),
                  content: _buildItem(
                    ArDriveIcons.folderAdd(size: 24),
                    appLocalizationsOf(context).uploadFolder,
                  ),
                ),
                ArDriveDropdownItem(
                  onClick: () {
                    promptToUpload(
                      context,
                      driveId: drive.id,
                      parentFolderId: currentFolder!.folder.id,
                      isFolderUpload: false,
                    );
                  },
                  content: _buildItem(
                    ArDriveIcons.uploadCloud(size: 24),
                    appLocalizationsOf(context).uploadFiles,
                  ),
                ),
                ArDriveDropdownItem(
                  onClick: () {
                    promptToCreateManifest(
                      context,
                      drive: drive,
                    );
                  },
                  content: _buildItem(
                    ArDriveIcons.manifest(size: 24),
                    appLocalizationsOf(context).createManifest,
                  ),
                ),
                ArDriveDropdownItem(
                  onClick: () {
                    promptToCreateSnapshot(
                      context,
                      drive,
                    );
                  },
                  content: _buildItem(
                    ArDriveIcons.camera(size: 24),
                    appLocalizationsOf(context).createSnapshot,
                  ),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ArDriveFAB(
                  backgroundColor: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeAccentBrand,
                  child: ArDriveIcons.plus(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(Widget icon, String text) {
    return ArDriveDropdownItem(
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(text, style: ArDriveTypography.body.buttonNormalBold()),
            const SizedBox(width: 8),
            icon,
          ],
        ),
      ),
    );
  }
}

// TODO: WIP!
class ArDriveGridItem extends StatelessWidget {
  const ArDriveGridItem({
    super.key,
    required this.item,
    required this.drive,
  });

  final ArDriveDataTableItem item;
  final Drive drive;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        item.onPressed(item);
      },
      child: ArDriveCard(
        contentPadding: const EdgeInsets.all(0),
        backgroundColor:
            ArDriveTheme.of(context).themeData.tableTheme.cellColor,
        content: Column(
          // mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.center,
                child: ArDriveFileIcon(
                  contentType: item.contentType,
                  size: 32,
                  fileStatus: item.fileStatusFromTransactions,
                ),
              ),
            ),
            Container(
              height: 41,
              padding: const EdgeInsets.only(left: 8, right: 4),
              color:
                  ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
              child: Row(
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            style: ArDriveTypography.body.buttonNormalBold(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Flexible(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Text(
                                item is FileDataTableItem
                                    ? filesize(item.size)
                                    : '-',
                                style: ArDriveTypography.body
                                    .xSmallRegular(
                                      color: ArDriveTheme.of(context)
                                          .themeData
                                          .colors
                                          .themeFgDefault
                                          .withOpacity(0.75),
                                    )
                                    .copyWith(
                                      fontSize: 8,
                                    ),
                              ),
                              const SizedBox(width: 8),
                              // last updated
                              Flexible(
                                child: Text(
                                  '${appLocalizationsOf(context).lastUpdated}: ${yMMdDateFormatter.format(item.lastUpdated)}',
                                  style: ArDriveTypography.body
                                      .xSmallRegular()
                                      .copyWith(
                                        fontSize: 8,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  DriveExplorerItemTileTrailing(
                    drive: drive,
                    item: item,
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
