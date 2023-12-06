import 'dart:async';
import 'dart:math';

import 'package:ardrive/app_shell.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/components/app_bottom_bar.dart';
import 'package:ardrive/components/app_top_bar.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/csv_export_dialog.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/components/drive_detach_dialog.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/new_button/new_button.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/download/multiple_file_download_modal.dart';
import 'package:ardrive/entities/entities.dart' as entities;
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/drive_file_drop_zone.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/file_icon.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/components/unpreviewable_content.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/compare_alphabetically_and_natural.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/mobile_screen_orientation.dart';
import 'package:ardrive/utils/mobile_status_bar.dart';
import 'package:ardrive/utils/plausible_event_tracker.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:synchronized/synchronized.dart';
import 'package:timeago/timeago.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

part 'components/drive_detail_breadcrumb_row.dart';
part 'components/drive_detail_data_list.dart';
part 'components/drive_detail_data_table_source.dart';
part 'components/drive_detail_folder_empty_card.dart';
part 'components/fs_entry_preview_widget.dart';

class DriveDetailPage extends StatefulWidget {
  final bool anonymouslyShowDriveDetail;

  const DriveDetailPage({
    Key? key,
    required this.anonymouslyShowDriveDetail,
  }) : super(key: key);

  @override
  State<DriveDetailPage> createState() => _DriveDetailPageState();
}

class _DriveDetailPageState extends State<DriveDetailPage> {
  bool checkboxEnabled = false;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    if (widget.anonymouslyShowDriveDetail) {
      PlausibleEventTracker.trackPageview(
          event: PlausiblePageView.fileExplorerNonLoggedInUser);
    } else {
      PlausibleEventTracker.trackPageview(
          event: PlausiblePageView.fileExplorerLoggedInUser);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: BlocBuilder<DriveDetailCubit, DriveDetailState>(
        builder: (context, driveDetailState) {
          if (driveDetailState is DriveDetailLoadInProgress) {
            return const Center(child: CircularProgressIndicator());
          } else if (driveDetailState is DriveInitialLoading) {
            return ScreenTypeLayout.builder(
              mobile: (context) {
                return Scaffold(
                  drawerScrimColor: Colors.transparent,
                  drawer: const AppSideBar(),
                  appBar: const MobileAppBar(),
                  body: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Center(
                      child: Text(
                        appLocalizationsOf(context)
                            .driveDoingInitialSetupMessage,
                        style: ArDriveTypography.body.buttonLargeBold(),
                      ),
                    ),
                  ),
                );
              },
              desktop: (context) => Scaffold(
                drawerScrimColor: Colors.transparent,
                body: Column(
                  children: [
                    const AppTopBar(),
                    Expanded(
                      child: Center(
                        child: Text(
                          appLocalizationsOf(context)
                              .driveDoingInitialSetupMessage,
                          style: ArDriveTypography.body.buttonLargeBold(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else if (driveDetailState is DriveDetailLoadSuccess) {
            final hasSubfolders =
                driveDetailState.folderInView.subfolders.isNotEmpty;

            final isOwner = isDriveOwner(
              context.read<ArDriveAuth>(),
              driveDetailState.currentDrive.ownerAddress,
            );

            final hasFiles = driveDetailState.folderInView.files.isNotEmpty;

            final canDownloadMultipleFiles = driveDetailState.multiselect &&
                context.read<DriveDetailCubit>().selectedItems.isNotEmpty;

            return ScreenTypeLayout.builder(
              desktop: (context) => _desktopView(
                isDriveOwner: isOwner,
                driveDetailState: driveDetailState,
                hasSubfolders: hasSubfolders,
                hasFiles: hasFiles,
                canDownloadMultipleFiles: canDownloadMultipleFiles,
              ),
              mobile: (context) => Scaffold(
                drawerScrimColor: Colors.transparent,
                drawer: const AppSideBar(),
                appBar: (driveDetailState.showSelectedItemDetails &&
                        context.read<DriveDetailCubit>().selectedItem != null)
                    ? MobileAppBar(
                        leading: ArDriveIconButton(
                          icon: ArDriveIcons.arrowLeft(),
                          onPressed: () {
                            context
                                .read<DriveDetailCubit>()
                                .toggleSelectedItemDetails();
                          },
                        ),
                      )
                    : null,
                body: _mobileView(
                  driveDetailState,
                  hasSubfolders,
                  hasFiles,
                  driveDetailState.currentFolderContents,
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
    required DriveDetailLoadSuccess driveDetailState,
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
                      padding: const EdgeInsets.fromLTRB(0, 0, 16, 0),
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
                                  path:
                                      driveDetailState.folderInView.folder.path,
                                  driveName: driveDetailState.currentDrive.name,
                                ),
                                const Spacer(),
                                if (driveDetailState.multiselect &&
                                    context
                                        .read<DriveDetailCubit>()
                                        .selectedItems
                                        .isNotEmpty &&
                                    isDriveOwner)
                                  ArDriveIconButton(
                                    tooltip: appLocalizationsOf(context).move,
                                    icon: ArDriveIcons.move(),
                                    onPressed: () {
                                      promptToMove(
                                        context,
                                        driveId:
                                            driveDetailState.currentDrive.id,
                                        selectedItems: context
                                            .read<DriveDetailCubit>()
                                            .selectedItems,
                                      );
                                    },
                                  ),
                                const SizedBox(width: 8),
                                if (canDownloadMultipleFiles &&
                                    context
                                        .read<ConfigService>()
                                        .config
                                        .enableMultipleFileDownload) ...[
                                  ArDriveIconButton(
                                    tooltip: 'Download selected files',
                                    icon: ArDriveIcons.download2(),
                                    onPressed: () async {
                                      final selectedItems = context
                                          .read<DriveDetailCubit>()
                                          .selectedItems;

                                      String zipName;

                                      if (selectedItems.length == 1 &&
                                          selectedItems[0]
                                              is FolderDataTableItem) {
                                        zipName = selectedItems[0].name;
                                      } else {
                                        final driveDetail = (context
                                            .read<DriveDetailCubit>()
                                            .state as DriveDetailLoadSuccess);

                                        final currentFolder =
                                            driveDetail.folderInView.folder;
                                        zipName =
                                            currentFolder.parentFolderId == null
                                                ? driveDetail.currentDrive.name
                                                : currentFolder.name;
                                      }

                                      promptToDownloadMultipleFiles(context,
                                          selectedItems: selectedItems,
                                          zipName: zipName);
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (driveDetailState.multiselect)
                                  const SizedBox(
                                    height: 24,
                                    child: VerticalDivider(),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 16.0),
                                  child: ArDriveClickArea(
                                    tooltip:
                                        appLocalizationsOf(context).showMenu,
                                    child: ArDriveDropdown(
                                      anchor: const Aligned(
                                        follower: Alignment.topRight,
                                        target: Alignment.bottomRight,
                                      ),
                                      items: [
                                        ArDriveDropdownItem(
                                          onClick: () async {
                                            final driveItem =
                                                DriveDataTableItemMapper
                                                    .fromDrive(
                                                        driveDetailState
                                                            .currentDrive,
                                                        (p0) => null,
                                                        0,
                                                        true);

                                            promptToDownloadMultipleFiles(
                                                context,
                                                selectedItems: [driveItem],
                                                zipName: driveItem.name);
                                          },
                                          content: ArDriveDropdownItemTile(
                                            name: appLocalizationsOf(context)
                                                .download,
                                            icon: ArDriveIcons.download2(
                                              size: defaultIconSize,
                                            ),
                                          ),
                                        ),
                                        if (isDriveOwner)
                                          ArDriveDropdownItem(
                                            onClick: () {
                                              promptToRenameDrive(
                                                context,
                                                driveId: driveDetailState
                                                    .currentDrive.id,
                                                driveName: driveDetailState
                                                    .currentDrive.name,
                                              );
                                            },
                                            content: ArDriveDropdownItemTile(
                                              name: appLocalizationsOf(context)
                                                  .renameDrive,
                                              icon: ArDriveIcons.edit(
                                                size: defaultIconSize,
                                              ),
                                            ),
                                          ),
                                        ArDriveDropdownItem(
                                          onClick: () {
                                            promptToShareDrive(
                                              context: context,
                                              drive:
                                                  driveDetailState.currentDrive,
                                            );
                                          },
                                          content: ArDriveDropdownItemTile(
                                            name: appLocalizationsOf(context)
                                                .shareDrive,
                                            icon: ArDriveIcons.share(
                                              size: defaultIconSize,
                                            ),
                                          ),
                                        ),
                                        ArDriveDropdownItem(
                                          onClick: () {
                                            promptToExportCSVData(
                                              context: context,
                                              driveId: driveDetailState
                                                  .currentDrive.id,
                                            );
                                          },
                                          content: ArDriveDropdownItemTile(
                                            name: appLocalizationsOf(context)
                                                .exportDriveContents,
                                            icon: ArDriveIcons.download2(
                                              size: defaultIconSize,
                                            ),
                                          ),
                                        ),
                                        ArDriveDropdownItem(
                                          onClick: () {
                                            final bloc = context
                                                .read<DriveDetailCubit>();

                                            bloc.selectDataItem(
                                              DriveDataTableItemMapper
                                                  .fromDrive(
                                                driveDetailState.currentDrive,
                                                (_) => null,
                                                0,
                                                isDriveOwner,
                                              ),
                                            );
                                          },
                                          content: _buildItem(
                                            appLocalizationsOf(context)
                                                .moreInfo,
                                            ArDriveIcons.info(
                                              size: defaultIconSize,
                                            ),
                                          ),
                                        ),
                                        if (!driveDetailState
                                                .hasWritePermissions &&
                                            !isDriveOwner &&
                                            context.read<ProfileCubit>().state
                                                is ProfileLoggedIn)
                                          ArDriveDropdownItem(
                                            onClick: () {
                                              showDetachDriveDialog(
                                                context: context,
                                                driveID: driveDetailState
                                                    .currentDrive.id,
                                                driveName: driveDetailState
                                                    .currentDrive.name,
                                              );
                                            },
                                            content: _buildItem(
                                              appLocalizationsOf(context)
                                                  .detachDrive,
                                              ArDriveIcons.detach(),
                                            ),
                                          ),
                                      ],
                                      child: HoverWidget(
                                        child: ArDriveIcons.kebabMenu(),
                                      ),
                                    ),
                                  ),
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
                                      driveDetailState,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Expanded(
                              child: DriveDetailFolderEmptyCard(
                                driveId: driveDetailState.currentDrive.id,
                                parentFolderId:
                                    driveDetailState.folderInView.folder.id,
                                promptToAddFiles:
                                    driveDetailState.hasWritePermissions,
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
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: _getMaxWidthForDetailsPanel(
                                driveDetailState, context),
                            minWidth: _getMinWidthForDetailsPanel(
                                driveDetailState, context),
                          ),
                          child: driveDetailState.showSelectedItemDetails &&
                                  context
                                          .read<DriveDetailCubit>()
                                          .selectedItem !=
                                      null
                              ? DetailsPanel(
                                  currentDrive: driveDetailState.currentDrive,
                                  isSharePage: false,
                                  drivePrivacy:
                                      driveDetailState.currentDrive.privacy,
                                  maybeSelectedItem:
                                      driveDetailState.maybeSelectedItem(),
                                  item: context
                                      .read<DriveDetailCubit>()
                                      .selectedItem!,
                                  onNextImageNavigation: () {
                                    context
                                        .read<DriveDetailCubit>()
                                        .selectNextImage();
                                  },
                                  onPreviousImageNavigation: () {
                                    context
                                        .read<DriveDetailCubit>()
                                        .selectPreviousImage();
                                  },
                                  canNavigateThroughImages: context
                                      .read<DriveDetailCubit>()
                                      .canNavigateThroughImages(),
                                )
                              : const SizedBox(),
                        ),
                      ))
                ],
              ),
              if (kIsWeb)
                DriveFileDropZone(
                  driveId: driveDetailState.currentDrive.id,
                  folderId: driveDetailState.folderInView.folder.id,
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
    DriveDetailLoadSuccess state,
    bool hasSubfolders,
    bool hasFiles,
    List<ArDriveDataTableItem> items,
  ) {
    if (state.showSelectedItemDetails &&
        context.read<DriveDetailCubit>().selectedItem != null) {
      return Material(
        child: WillPopScope(
          onWillPop: () async {
            context.read<DriveDetailCubit>().toggleSelectedItemDetails();
            return false;
          },
          child: DetailsPanel(
            currentDrive: state.currentDrive,
            isSharePage: false,
            drivePrivacy: state.currentDrive.privacy,
            maybeSelectedItem: state.maybeSelectedItem(),
            item: context.read<DriveDetailCubit>().selectedItem!,
            onNextImageNavigation: () {
              context.read<DriveDetailCubit>().selectNextImage();
            },
            onPreviousImageNavigation: () {
              context.read<DriveDetailCubit>().selectPreviousImage();
            },
            canNavigateThroughImages:
                context.read<DriveDetailCubit>().canNavigateThroughImages(),
          ),
        ),
      );
    }

    return Scaffold(
      drawerScrimColor: ArDriveTheme.of(context)
          .themeData
          .colors
          .themeBgSurface
          .withOpacity(0.5),
      drawer: const AppSideBar(),
      appBar: MobileAppBar(
        leading: (state.showSelectedItemDetails &&
                context.read<DriveDetailCubit>().selectedItem != null)
            ? ArDriveIconButton(
                icon: ArDriveIcons.arrowLeft(),
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

  Widget _mobileViewContent(
    DriveDetailLoadSuccess state,
    bool hasSubfolders,
    bool hasFiles,
    List<ArDriveDataTableItem> items,
  ) {
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
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 16,
            ),
            child: (hasSubfolders || hasFiles)
                ? ListView.separated(
                    controller: _scrollController,
                    separatorBuilder: (context, index) => const SizedBox(
                      height: 5,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      return ArDriveItemListTile(
                        key: ObjectKey([items[index]]),
                        drive: state.currentDrive,
                        item: items[index],
                      );
                    },
                  )
                : DriveDetailFolderEmptyCard(
                    promptToAddFiles: state.hasWritePermissions,
                    driveId: state.currentDrive.id,
                    parentFolderId: state.folderInView.folder.id,
                  ),
          ),
        ),
      ],
    );
  }

  _buildItem(String name, ArDriveIcon icon) {
    return ArDriveDropdownItemTile(name: name, icon: icon);
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
    return ArDriveCard(
      backgroundColor:
          ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
      content: InkWell(
        onTap: () {
          final cubit = context.read<DriveDetailCubit>();
          if (item is FolderDataTableItem) {
            cubit.openFolder(path: item.path);
          } else if (item is FileDataTableItem) {
            if (item.id == cubit.selectedItem?.id) {
              cubit.toggleSelectedItemDetails();
              return;
            }
            cubit.selectDataItem(item);
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            DriveExplorerItemTileLeading(
              item: item,
            ),
            const SizedBox(
              width: 12,
            ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: ArDriveTypography.body
                        .captionRegular()
                        .copyWith(fontWeight: FontWeight.w700),
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
            DriveExplorerItemTileTrailing(
              item: item,
              drive: drive,
            )
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                context
                    .read<DriveDetailCubit>()
                    .openFolder(path: getParentFolderPath(path));
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (path.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 8,
                        top: 4,
                      ),
                      child: ArDriveIcons.arrowLeft(),
                    ),
                  Expanded(
                    child: Padding(
                      padding: path.isEmpty
                          ? const EdgeInsets.only(left: 16, top: 6, bottom: 6)
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
                  anchor: const Aligned(
                    follower: Alignment.topRight,
                    target: Alignment.bottomRight,
                  ),
                  items: [
                    ArDriveDropdownItem(
                        onClick: () async {
                          final driveItem = DriveDataTableItemMapper.fromDrive(
                              state.currentDrive, (p0) => null, 0, true);

                          promptToDownloadMultipleFiles(context,
                              selectedItems: [driveItem],
                              zipName: driveItem.name);
                        },
                        content: ArDriveDropdownItemTile(
                          name: appLocalizationsOf(context).download,
                          icon: ArDriveIcons.download2(
                            size: defaultIconSize,
                          ),
                        )),
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
                          ArDriveIcons.edit(
                            size: defaultIconSize,
                          ),
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
                        ArDriveIcons.share(
                          size: defaultIconSize,
                        ),
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
                        ArDriveIcons.download2(
                          size: defaultIconSize,
                        ),
                      ),
                    ),
                    ArDriveDropdownItem(
                      onClick: () {
                        final bloc = context.read<DriveDetailCubit>();

                        bloc.selectDataItem(
                          DriveDataTableItemMapper.fromDrive(
                            state.currentDrive,
                            (_) => null,
                            0,
                            isOwner,
                          ),
                        );
                      },
                      content: _buildItem(
                        appLocalizationsOf(context).moreInfo,
                        ArDriveIcons.info(
                          size: defaultIconSize,
                        ),
                      ),
                    ),
                    if (!state.hasWritePermissions &&
                        !isOwner &&
                        context.read<ProfileCubit>().state is ProfileLoggedIn)
                      ArDriveDropdownItem(
                        onClick: () {
                          showDetachDriveDialog(
                            context: context,
                            driveID: state.currentDrive.id,
                            driveName: state.currentDrive.name,
                          );
                        },
                        content: _buildItem(
                          appLocalizationsOf(context).detachDrive,
                          ArDriveIcons.detach(),
                        ),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 8,
                    ),
                    child: HoverWidget(
                      child: ArDriveIcons.kebabMenu(),
                    ),
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
    return ArDriveDropdownItemTile(
      name: name,
      icon: icon,
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
    this.drive,
    this.currentFolder,
  });

  final Drive? drive;
  final FolderWithContents? currentFolder;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = ArDriveTheme.of(context).themeData.backgroundColor;
    return Container(
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
          NewButton(
            isBottomNavigationButton: true,
            driveDetailState: context.read<DriveDetailCubit>().state,
            currentFolder: currentFolder,
            dropdownWidth: 208,
            anchor: const Aligned(
              follower: Alignment.bottomCenter,
              target: Alignment.topCenter,
            ),
            drive: drive,
            child: ArDriveFAB(
              backgroundColor:
                  ArDriveTheme.of(context).themeData.colors.themeAccentBrand,
              child: ArDriveIcons.plus(
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// TODO: WIP! It will be done in a further release.
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
        // item.onPressed(item);
      },
      child: ArDriveCard(
        contentPadding: const EdgeInsets.all(0),
        backgroundColor:
            ArDriveTheme.of(context).themeData.colors.themeBorderDefault,
        content: Column(
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
