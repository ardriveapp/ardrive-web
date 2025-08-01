import 'dart:async';
import 'dart:math';

import 'package:ardrive/app_shell.dart';
import 'package:ardrive/arns/presentation/ant_icon.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/components/breakpoint_layout_builder.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_state.dart';
import 'package:ardrive/components/app_bottom_bar.dart';
import 'package:ardrive/components/app_top_bar.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/create_snapshot_dialog.dart';
import 'package:ardrive/components/csv_export_dialog.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/components/drive_detach_dialog.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/fs_entry_license_form.dart';
import 'package:ardrive/components/hide_dialog.dart';
import 'package:ardrive/components/keyboard_handler.dart';
import 'package:ardrive/components/new_button/new_button.dart';
import 'package:ardrive/components/pin_file_dialog.dart';
import 'package:ardrive/components/prompt_to_snapshot_dialog.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/dev_tools/app_dev_tools.dart';
import 'package:ardrive/dev_tools/shortcut_handler.dart';
import 'package:ardrive/download/multiple_file_download_modal.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/drive_file_drop_zone.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/file_icon.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/components/unpreviewable_content.dart';
import 'package:ardrive/pages/drive_detail/components/document_preview_widget.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/no_drives/no_drives_page.dart';
import 'package:ardrive/search/search_modal.dart';
import 'package:ardrive/search/search_text_field.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/shared/components/plausible_page_view_wrapper.dart';
import 'package:ardrive/sharing/sharing_file_listener.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/compare_alphabetically_and_natural.dart';
import 'package:ardrive/utils/has_arns_name.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/mobile_screen_orientation.dart';
import 'package:ardrive/utils/mobile_status_bar.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:synchronized/synchronized.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

part 'components/drive_detail_breadcrumb_row.dart';
part 'components/drive_detail_data_list.dart';
part 'components/drive_detail_folder_empty_card.dart';
part 'components/fs_entry_preview_widget.dart';

class DriveDetailPage extends StatefulWidget {
  final bool anonymouslyShowDriveDetail;
  final BuildContext context;

  const DriveDetailPage({
    required this.context,
    super.key,
    required this.anonymouslyShowDriveDetail,
  });

  @override
  State<DriveDetailPage> createState() => _DriveDetailPageState();
}

class _DriveDetailPageState extends State<DriveDetailPage> {
  bool checkboxEnabled = false;
  final _scrollController = ScrollController();
  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();

    if (widget.anonymouslyShowDriveDetail) {
      PlausibleEventTracker.trackPageview(
        page: PlausiblePageView.fileExplorerPage,
        props: {
          'loggedIn': false,
          'noDrives': false,
        },
      );
      // FIXME: remove below
      PlausibleEventTracker.trackPageview(
        page: PlausiblePageView.fileExplorerNonLoggedInUser,
      );
    } else {
      PlausibleEventTracker.trackPageview(
        page: PlausiblePageView.fileExplorerPage,
        props: {
          'loggedIn': true,
          'noDrives': false,
        },
      );
      // FIXME: remove below
      PlausibleEventTracker.trackPageview(
        page: PlausiblePageView.fileExplorerLoggedInUser,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SharingFileListener(
      context: widget.context,
      child: SizedBox.expand(
        child: BlocListener<DrivesCubit, DrivesState>(
          listener: (context, state) {
            if (state is DrivesLoadSuccess) {
              if (state.userDrives.isNotEmpty ||
                  state.sharedDrives.isNotEmpty) {
                final driveDetailState = context.read<DriveDetailCubit>().state;

                if (driveDetailState is DriveDetailLoadSuccess &&
                    driveDetailState.currentDrive.id == state.selectedDriveId) {
                  return;
                }

                context
                    .read<DriveDetailCubit>()
                    .changeDrive(state.selectedDriveId!);
              } else {
                context.read<DriveDetailCubit>().showEmptyDriveDetail();
              }
            }
          },
          child: BlocListener<PromptToSnapshotBloc, PromptToSnapshotState>(
            listener: (context, state) {
              if (state is PromptToSnapshotPrompting) {
                final bloc = context.read<PromptToSnapshotBloc>();

                final driveDetailState = context.read<DriveDetailCubit>().state;
                if (driveDetailState is DriveDetailLoadSuccess) {
                  final drive = driveDetailState.currentDrive;
                  promptToSnapshot(
                    context,
                    promptToSnapshotBloc: bloc,
                    drive: drive,
                  ).then((_) {
                    bloc.add(const SelectedDrive(driveId: null));
                  });
                }
              }
            },
            child: BlocBuilder<GlobalHideBloc, GlobalHideState>(
              builder: (context, hideState) {
                return BlocBuilder<DriveDetailCubit, DriveDetailState>(
                  buildWhen: (previous, current) {
                    return !context.read<ActivityTracker>().isBulkImporting &&
                        widget.context.read<SyncCubit>().state
                            is! SyncInProgress;
                  },
                  builder: (context, driveDetailState) {
                    if (driveDetailState is DriveDetailLoadEmpty) {
                      return NoDrivesPage(
                        anonymouslyShowDriveDetail:
                            widget.anonymouslyShowDriveDetail,
                      );
                    } else if (driveDetailState is DriveDetailLoadInProgress) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (driveDetailState is DriveInitialLoading) {
                      return ArDriveDevToolsShortcuts(
                        customShortcuts: [
                          Shortcut(
                            modifier: LogicalKeyboardKey.shiftLeft,
                            key: LogicalKeyboardKey.keyH,
                            action: () {
                              ArDriveDevTools.instance
                                  .showDevTools(optionalContext: context);
                            },
                          ),
                        ],
                        child: ScreenTypeLayout.builder(
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
                                    style: ArDriveTypography.body
                                        .buttonLargeBold(),
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
                                      style: ArDriveTypography.body
                                          .buttonLargeBold(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    } else if (driveDetailState is DriveDetailLoadSuccess) {
                      final isShowingHiddenFiles =
                          hideState is ShowingHiddenItems;
                      final bool hasSubfolders;
                      final bool hasFiles;

                      if (isShowingHiddenFiles) {
                        hasSubfolders =
                            driveDetailState.folderInView.subfolders.isNotEmpty;
                        hasFiles =
                            driveDetailState.folderInView.files.isNotEmpty;
                      } else {
                        hasSubfolders = driveDetailState.folderInView.subfolders
                            .where((e) => !e.isHidden)
                            .isNotEmpty;
                        hasFiles = driveDetailState.folderInView.files
                            .where((e) => !e.isHidden)
                            .isNotEmpty;
                      }

                      final isOwner = isDriveOwner(
                        context.read<ArDriveAuth>(),
                        driveDetailState.currentDrive.ownerAddress,
                      );

                      final canDownloadMultipleFiles =
                          driveDetailState.multiselect &&
                              context
                                  .read<DriveDetailCubit>()
                                  .selectedItems
                                  .isNotEmpty;

                      return ArDriveDevToolsShortcuts(
                        customShortcuts: [
                          Shortcut(
                            modifier: LogicalKeyboardKey.shiftLeft,
                            key: LogicalKeyboardKey.keyH,
                            action: () {
                              ArDriveDevTools.instance
                                  .showDevTools(optionalContext: context);
                            },
                          ),
                        ],
                        child: ScreenTypeLayout.builder(
                          desktop: (context) => _desktopView(
                            isDriveOwner: isOwner,
                            driveDetailState: driveDetailState,
                            hasSubfolders: hasSubfolders,
                            hasFiles: hasFiles,
                            canDownloadMultipleFiles: canDownloadMultipleFiles,
                            hideState: hideState,
                          ),
                          mobile: (context) => Scaffold(
                            resizeToAvoidBottomInset: false,
                            drawerScrimColor: Colors.transparent,
                            drawer: const AppSideBar(),
                            appBar: (driveDetailState.showSelectedItemDetails &&
                                    context
                                            .read<DriveDetailCubit>()
                                            .selectedItem !=
                                        null)
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
                              hideState,
                            ),
                          ),
                        ),
                      );
                    } else {
                      return const SizedBox();
                    }
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopView({
    required DriveDetailLoadSuccess driveDetailState,
    required bool hasSubfolders,
    required bool hasFiles,
    required bool isDriveOwner,
    required bool canDownloadMultipleFiles,
    required GlobalHideState hideState,
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
                                  rootFolderId: driveDetailState
                                      .currentDrive.rootFolderId,
                                  path: driveDetailState.pathSegments,
                                  driveName: driveDetailState.currentDrive.name,
                                ),
                                const Spacer(),
                                if (driveDetailState.multiselect &&
                                    context
                                        .read<DriveDetailCubit>()
                                        .selectedItems
                                        .isNotEmpty &&
                                    isDriveOwner) ...[
                                  ArDriveIconButton(
                                    tooltip: 'Add license',
                                    // TODO: Localize
                                    // tooltip: appLocalizationsOf(context).addLicense,
                                    icon: ArDriveIcons.license(),
                                    onPressed: () {
                                      promptToLicense(
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
                                ],
                                const SizedBox(width: 8),
                                if (canDownloadMultipleFiles) ...[
                                  ArDriveIconButton(
                                    tooltip: 'Download selected files',
                                    icon: ArDriveIcons.download(),
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
                                            icon: ArDriveIcons.download(
                                              size: defaultIconSize,
                                            ),
                                          ),
                                        ),
                                        if (isDriveOwner) ...[
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
                                            content: _buildItem(
                                              appLocalizationsOf(context)
                                                  .renameDrive,
                                              ArDriveIcons.edit(
                                                size: defaultIconSize,
                                              ),
                                            ),
                                          ),
                                        ],
                                        ArDriveDropdownItem(
                                          onClick: () {
                                            promptToCreateSnapshot(context,
                                                driveDetailState.currentDrive);
                                          },
                                          content: _buildItem(
                                            appLocalizationsOf(context)
                                                .createSnapshot,
                                            ArDriveIcons.iconCreateSnapshot(
                                              size: defaultIconSize,
                                            ),
                                          ),
                                        ),
                                        if (isDriveOwner)
                                          ArDriveDropdownItem(
                                            onClick: () {
                                              promptToToggleHideState(
                                                context,
                                                item: DriveDataTableItemMapper
                                                    .fromDrive(
                                                  driveDetailState.currentDrive,
                                                  (_) => null,
                                                  0,
                                                  isDriveOwner,
                                                ),
                                              );
                                            },
                                            content: ArDriveDropdownItemTile(
                                              name: driveDetailState
                                                      .currentDrive.isHidden
                                                  ? appLocalizationsOf(context)
                                                      .unhide
                                                  : appLocalizationsOf(context)
                                                      .hide,
                                              icon: driveDetailState
                                                      .currentDrive.isHidden
                                                  ? ArDriveIcons.eyeOpen(
                                                      size: defaultIconSize,
                                                    )
                                                  : ArDriveIcons.eyeClosed(
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
                                            icon: ArDriveIcons.download(
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
                                      Column(
                                        children: [
                                          Expanded(
                                            child: DriveDetailFolderEmptyCard(
                                              driveId: driveDetailState
                                                  .currentDrive.id,
                                              parentFolderId: driveDetailState
                                                  .folderInView.folder.id,
                                              promptToAddFiles: driveDetailState
                                                  .hasWritePermissions,
                                              isRootFolder: driveDetailState
                                                      .folderInView
                                                      .folder
                                                      .parentFolderId ==
                                                  null,
                                            ),
                                          ),
                                        ],
                                      ),
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
                                isRootFolder: driveDetailState.folderInView
                                            .folder.parentFolderId ==
                                        null &&
                                    !hasSubfolders,
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
                                  driveDetailState.selectedItem != null
                              ? DetailsPanel(
                                  currentDrive: driveDetailState.currentDrive,
                                  isSharePage: false,
                                  drivePrivacy:
                                      driveDetailState.currentDrive.privacy,
                                  item: driveDetailState.selectedItem!,
                                  onNextImageNavigation: () {
                                    context
                                        .read<DriveDetailCubit>()
                                        .selectNextImage(
                                          hideState is ShowingHiddenItems,
                                        );
                                  },
                                  onPreviousImageNavigation: () {
                                    context
                                        .read<DriveDetailCubit>()
                                        .selectPreviousImage(
                                          hideState is ShowingHiddenItems,
                                        );
                                  },
                                  canNavigateThroughImages: context
                                      .read<DriveDetailCubit>()
                                      .canNavigateThroughImages(
                                        hideState is ShowingHiddenItems,
                                      ),
                                )
                              : const SizedBox(),
                        ),
                      ))
                ],
              ),
              if (kIsWeb && driveDetailState.hasWritePermissions)
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
    DriveDetailLoadSuccess driveDetailLoadSuccessState,
    bool hasSubfolders,
    bool hasFiles,
    GlobalHideState hideState,
  ) {
    final items = driveDetailLoadSuccessState.currentFolderContents;

    if (driveDetailLoadSuccessState.showSelectedItemDetails &&
        context.read<DriveDetailCubit>().selectedItem != null) {
      return Material(
        child: PopScope(
          canPop: false,
          onPopInvoked: (didPop) {
            context.read<DriveDetailCubit>().toggleSelectedItemDetails();
          },
          child: DetailsPanel(
            currentDrive: driveDetailLoadSuccessState.currentDrive,
            isSharePage: false,
            drivePrivacy: driveDetailLoadSuccessState.currentDrive.privacy,
            item: driveDetailLoadSuccessState.selectedItem!,
            onNextImageNavigation: () {
              context
                  .read<DriveDetailCubit>()
                  .selectNextImage(hideState is ShowingHiddenItems);
            },
            onPreviousImageNavigation: () {
              context
                  .read<DriveDetailCubit>()
                  .selectPreviousImage(hideState is ShowingHiddenItems);
            },
            canNavigateThroughImages: context
                .read<DriveDetailCubit>()
                .canNavigateThroughImages(hideState is ShowingHiddenItems),
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
        leading: (driveDetailLoadSuccessState.showSelectedItemDetails &&
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
        driveDetailLoadSuccessState,
        hasSubfolders,
        hasFiles,
        items,
        hideState,
      ),
    );
  }

  Widget _mobileViewContent(
    DriveDetailLoadSuccess state,
    bool hasSubfolders,
    bool hasFiles,
    List<ArDriveDataTableItem> items,
    GlobalHideState globalHideState,
  ) {
    final isShowingHiddenFiles = globalHideState is ShowingHiddenItems;

    final List<ArDriveDataTableItem> filteredItems;

    if (isShowingHiddenFiles) {
      filteredItems = items.toList();
    } else {
      filteredItems = items.where((item) => item.isHidden == false).toList();
    }

    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SearchTextField(
            controller: controller,
            onFieldSubmitted: (query) {
              if (query.isEmpty) {
                return;
              }

              showModalBottomSheet(
                isScrollControlled: true,
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) => Container(
                  height: MediaQuery.of(context).size.height * 0.85,
                  decoration: BoxDecoration(
                    color: colorTokens.containerL2,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6.0),
                      topRight: Radius.circular(6.0),
                    ),
                  ),
                  child: Padding(
                    padding: MediaQuery.of(context).viewInsets,
                    child: BlocProvider.value(
                      value: context.read<DriveDetailCubit>(),
                      child: FileSearchModal(
                        initialQuery: query,
                        driveDetailCubit: context.read<DriveDetailCubit>(),
                        controller: controller,
                        drivesCubit: context.read<DrivesCubit>(),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Flexible(
                child: MobileFolderNavigation(
                  driveName: state.currentDrive.name,
                  path: state.pathSegments,
                  isShowingHiddenFiles: isShowingHiddenFiles,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: (hasSubfolders || hasFiles)
              ? ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  controller: _scrollController,
                  separatorBuilder: (context, index) => const SizedBox(
                    height: 5,
                  ),
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    return ArDriveItemListTile(
                      key: ObjectKey([filteredItems[index]]),
                      drive: state.currentDrive,
                      item: filteredItems[index],
                    );
                  },
                )
              : DriveDetailFolderEmptyCard(
                  promptToAddFiles: state.hasWritePermissions,
                  driveId: state.currentDrive.id,
                  parentFolderId: state.folderInView.folder.id,
                  isRootFolder:
                      state.folderInView.folder.parentFolderId == null,
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
            cubit.openFolder(folderId: item.id);
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          style:
                              ArDriveTypography.body.captionRegular().copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: item.isHidden ? Colors.grey : null,
                                  ),
                        ),
                      ),
                      if (hasArnsNames(item)) ...[
                        const SizedBox(width: 8),
                        Transform(
                          transform: Matrix4.translationValues(0, 2, 0),
                          child: AntIcon(
                              fileDataTableItem: item as FileDataTableItem),
                        ),
                      ],
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
  final List<BreadCrumbRowInfo> path;
  final String driveName;
  final bool isShowingHiddenFiles;

  const MobileFolderNavigation({
    super.key,
    required this.path,
    required this.driveName,
    required this.isShowingHiddenFiles,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 45,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SizedBox(
              height: 45,
              child: InkWell(
                onTap: () {
                  if (path.length == 1) {
                    // If we are at the root folder, open the drive
                    context.read<DriveDetailCubit>().openFolder();
                    return;
                  }
                  String? targetId;

                  if (path.isNotEmpty) {
                    targetId = path.first.targetId;
                  }

                  context
                      .read<DriveDetailCubit>()
                      .openFolder(folderId: targetId);
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
                          _pathToName(
                            path.isEmpty ? driveName : path.last.text,
                          ),
                          style: ArDriveTypography.body.buttonNormalBold(),
                        ),
                      ),
                    ),
                  ],
                ),
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
                          icon: ArDriveIcons.download(
                            size: defaultIconSize,
                          ),
                        )),
                    if (isOwner) ...[
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
                          promptToCreateSnapshot(context, state.currentDrive);
                        },
                        content: _buildItem(
                          appLocalizationsOf(context).createSnapshot,
                          ArDriveIcons.iconCreateSnapshot(
                            size: defaultIconSize,
                          ),
                        ),
                      ),
                    ],
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
                    if (isOwner)
                      ArDriveDropdownItem(
                        onClick: () {
                          promptToToggleHideState(
                            context,
                            item: DriveDataTableItemMapper.fromDrive(
                              state.currentDrive,
                              (_) => null,
                              0,
                              isOwner,
                            ),
                          );
                        },
                        content: ArDriveDropdownItemTile(
                          name: state.currentDrive.isHidden
                              ? appLocalizationsOf(context).unhide
                              : appLocalizationsOf(context).hide,
                          icon: state.currentDrive.isHidden
                              ? ArDriveIcons.eyeOpen(
                                  size: defaultIconSize,
                                )
                              : ArDriveIcons.eyeClosed(
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
                        ArDriveIcons.download(
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
