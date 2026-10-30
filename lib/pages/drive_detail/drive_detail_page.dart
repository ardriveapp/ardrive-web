import 'dart:async';
import 'dart:math';

import 'package:ardrive/locked_drives/presentation/locked_drive_view.dart';
import 'package:ardrive/arns/presentation/item/arns_item_names.dart';
import 'package:ardrive/app_shell.dart';
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
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/components/fs_entry_license_form.dart';
import 'package:ardrive/components/keyboard_handler.dart';
import 'package:ardrive/components/new_button/new_button.dart';
import 'package:ardrive/components/pin_file_dialog.dart';
import 'package:ardrive/components/private_drive_marks.dart';
import 'package:ardrive/components/prompt_to_snapshot_dialog.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/dev_tools/app_dev_tools.dart';
import 'package:ardrive/dev_tools/shortcut_handler.dart';
import 'package:ardrive/download/multiple_file_download_modal.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/publication/presentation/publication_chrome.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/drive_detail_syncing_card.dart';
import 'package:ardrive/pages/drive_detail/components/drive_file_drop_zone.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/syncing_drive_notice.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/components/item_menus.dart';
import 'package:ardrive/pages/drive_detail/components/unpreviewable_content.dart';
import 'package:ardrive/pages/drive_detail/components/document_preview_widget.dart';
import 'package:ardrive/pages/drive_detail/components/email_preview_widget.dart';
import 'package:ardrive/pages/drive_detail/components/pdf_preview_widget.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/no_drives/first_drive_page.dart';
import 'package:ardrive/pages/no_drives/no_drives_page.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/shared/components/plausible_page_view_wrapper.dart';
import 'package:ardrive/sharing/sharing_file_listener.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/compare_alphabetically_and_natural.dart';
import 'package:ardrive/utils/file_type_label.dart';
import 'package:ardrive/utils/format_date.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/mobile_screen_orientation.dart';
import 'package:ardrive/utils/mobile_status_bar.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
part 'components/drive_detail_unsynced_card.dart';
part 'components/fs_entry_preview_widget.dart';

/// The gap under a folder's heading on a wide screen, before whatever the
/// folder shows: its table, or any empty, syncing or unsynced card. Set here
/// once; the cards add none of their own above, so every state starts where
/// the table does.
const double explorerHeadingGap = ArDriveSpacing.xl;

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

  /// How far down the phone's list each folder visited was scrolled.
  ///
  /// The list is one widget for every folder, so without this a folder opened
  /// from halfway down its parent opened halfway down too, and going back to
  /// the parent started it from wherever the child had been left. A folder
  /// now opens at its top, and the one gone back to opens where it was.
  final _mobileScrollOffsets = <String, double>{};
  String? _mobileFolderId;

  /// A publication root's header folds away while the list beneath it is
  /// scrolled, so the list has the window, and unfolds at its top.
  bool _publicationHeaderFolded = false;
  String? _publicationHeaderFolderId;
  bool _publicationListCanScroll = false;
  bool _publicationListAtTop = true;

  void _onMobileFolderShown(String folderId) {
    if (_mobileFolderId == folderId) {
      return;
    }

    final previous = _mobileFolderId;
    if (previous != null && _scrollController.hasClients) {
      _mobileScrollOffsets[previous] = _scrollController.offset;
    }
    _mobileFolderId = folderId;

    final target = _mobileScrollOffsets[folderId] ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      _scrollController.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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
                final cubit = context.read<DriveDetailCubit>();

                // Don't re-trigger changeDrive if we're already viewing/loading
                // this drive — UNLESS nothing of it is on screen: not found,
                // or the no-drives screens a visitor gets while the drive a
                // link named is being attached. In either case it may have
                // been attached since we last checked.
                final showingNoDrive = cubit.state is DriveDetailLoadNotFound ||
                    cubit.state is DriveDetailLoadEmpty ||
                    cubit.state is DriveDetailDrivesUnavailable;
                if (cubit.currentDriveId == state.selectedDriveId &&
                    !showingNoDrive) {
                  return;
                }

                cubit.changeDrive(state.selectedDriveId!);
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
                    return !context.read<ActivityTracker>().isBulkImporting;
                  },
                  builder: (context, driveDetailState) {
                    if (driveDetailState is DriveDetailLoadEmpty) {
                      if (widget.anonymouslyShowDriveDetail) {
                        return NoDrivesPage(anonymouslyShowDriveDetail: true);
                      }
                      return FirstDrivePage(
                        noDrives: (_) =>
                            NoDrivesPage(anonymouslyShowDriveDetail: false),
                      );
                    } else if (driveDetailState is DriveDetailLoadInProgress) {
                      // Same chrome as before - only the middle of the panel
                      // changes, so nothing around it moves when the wait ends
                      // - and the same widget on both, because the surface with
                      // less room and no hover is the last one that should be
                      // told less.
                      return ScreenTypeLayout.builder(
                        mobile: (context) => Scaffold(
                          drawerScrimColor: Colors.transparent,
                          drawer:
                              PublicationMode.isOn ? null : const AppSideBar(),
                          appBar: const MobileAppBar(),
                          body: const DriveDetailSyncingCard(),
                        ),
                        desktop: (context) => const Column(
                          children: [
                            AppTopBar(),
                            // The margin the unsynced card already has. Without
                            // it this panel ran to the window's right edge
                            // while every other full-panel state stopped short
                            // of it.
                            Expanded(
                              child: Padding(
                                // No heading above this panel, so the gap
                                // is to the top bar; the card has none of
                                // its own.
                                padding: EdgeInsets.only(top: 20, right: 16),
                                child: DriveDetailSyncingCard(),
                              ),
                            ),
                          ],
                        ),
                      );
                    } else if (driveDetailState
                        is DriveDetailDrivesUnavailable) {
                      // The same chrome and the same panel as the wait above,
                      // because it is the end of that wait - only the words
                      // change. Notably NOT NoDrivesPage: we do not know that
                      // the user has no drives, so we do not say so and do not
                      // put two create-a-drive buttons where the answer should
                      // be.
                      return ScreenTypeLayout.builder(
                        mobile: (context) => Scaffold(
                          drawerScrimColor: Colors.transparent,
                          drawer:
                              PublicationMode.isOn ? null : const AppSideBar(),
                          appBar: const MobileAppBar(),
                          body: const DriveDetailSyncingCard
                              .driveListUnavailable(),
                        ),
                        desktop: (context) => const Column(
                          children: [
                            AppTopBar(),
                            Expanded(
                              child: Padding(
                                // No heading above this panel, so the gap
                                // is to the top bar; the card has none of
                                // its own.
                                padding: EdgeInsets.only(top: 20, right: 16),
                                child: DriveDetailSyncingCard
                                    .driveListUnavailable(),
                              ),
                            ),
                          ],
                        ),
                      );
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
                              drawer: PublicationMode.isOn
                                  ? null
                                  : const AppSideBar(),
                              appBar: const MobileAppBar(),
                              body: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Center(
                                  child: Text(
                                    appLocalizationsOf(context)
                                        .driveDoingInitialSetupMessage,
                                    style: ArDriveTypographyNew.of(context)
                                        .paragraphLarge(
                                            fontWeight: ArFontWeight.semiBold),
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
                                      style: ArDriveTypographyNew.of(context)
                                          .paragraphLarge(
                                              fontWeight:
                                                  ArFontWeight.semiBold),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    } else if (driveDetailState is DriveDetailLoadUnsynced) {
                      final isOwner = isDriveOwner(
                        context.read<ArDriveAuth>(),
                        driveDetailState.drive.ownerAddress,
                      );

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
                            // Show full-screen DetailsPanel on mobile when drive info is selected
                            if (driveDetailState.showDriveInfo &&
                                driveDetailState.selectedItem != null) {
                              return Material(
                                child: PopScope(
                                  canPop: false,
                                  onPopInvoked: (didPop) {
                                    context
                                        .read<DriveDetailCubit>()
                                        .closeDriveInfoForUnsyncedDrive();
                                  },
                                  child: DetailsPanel(
                                    currentDrive: driveDetailState.drive,
                                    item: driveDetailState.selectedItem!,
                                    canNavigateThroughImages: false,
                                  ),
                                ),
                              );
                            }
                            return Scaffold(
                              drawerScrimColor: Colors.transparent,
                              drawer: PublicationMode.isOn
                                  ? null
                                  : const AppSideBar(),
                              appBar: const MobileAppBar(),
                              body: _UnsyncedDriveMobileView(
                                drive: driveDetailState.drive,
                                isOwner: isOwner,
                                syncFoundNothing:
                                    driveDetailState.syncFoundNothing,
                              ),
                            );
                          },
                          desktop: (context) => Column(
                            children: [
                              const AppTopBar(),
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            0, 0, 16, 0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _UnsyncedDriveHeader(
                                              drive: driveDetailState.drive,
                                              isOwner: isOwner,
                                            ),
                                            const SizedBox(
                                              height: explorerHeadingGap,
                                            ),
                                            Expanded(
                                              child: DriveDetailUnsyncedCard(
                                                drive: driveDetailState.drive,
                                                syncFoundNothing:
                                                    driveDetailState
                                                        .syncFoundNothing,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // Details panel for unsynced drive
                                    if (driveDetailState.showDriveInfo &&
                                        driveDetailState.selectedItem != null)
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 420,
                                          minWidth: 310,
                                        ),
                                        child: DetailsPanel(
                                          item: driveDetailState.selectedItem!,
                                          canNavigateThroughImages: false,
                                          currentDrive: driveDetailState.drive,
                                          // It had no close of its own: the
                                          // toolbar only drew for a loaded
                                          // drive.
                                          onClose: () => context
                                              .read<DriveDetailCubit>()
                                              .closeDriveInfoForUnsyncedDrive(),
                                          onSync: () => context
                                              .read<DriveDetailCubit>()
                                              .syncCurrentDrive(),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    } else if (driveDetailState is DriveDetailLoadSuccess) {
                      final isShowingHiddenFiles =
                          hideState is ShowingHiddenItems;
                      final bool hasSubfolders;
                      final bool hasFiles;

                      if (PublicationMode.isOn) {
                        // What the publication shows, as the table lists it: a
                        // folder of only hidden items, ghost folders or
                        // unconfirmed uploads is empty there.
                        final contents = driveDetailState.currentFolderContents;
                        hasSubfolders =
                            contents.any((e) => e is FolderDataTableItem);
                        hasFiles = contents.any((e) => e is FileDataTableItem);
                      } else if (isShowingHiddenFiles) {
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
                            drawer: PublicationMode.isOn
                                ? null
                                : const AppSideBar(),
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
                    } else if (driveDetailState is DriveDetailLoadNotFound &&
                        context.read<AppRouterDelegate>().sharedDriveKey ==
                            null) {
                      // A private drive of the user's that this session
                      // can't open. A link that brought its key goes on to
                      // attach as it always has.
                      // Only that: anyone else - a visitor without the
                      // key, a drive that doesn't exist - gets what they
                      // always got here, nothing, with the attach dialog
                      // over it. The shell is drawn only for a locked drive.
                      return LockedDriveView(
                        driveId:
                            context.read<DriveDetailCubit>().currentDriveId,
                        otherwise: const SizedBox(),
                        frame: (panel) => ScreenTypeLayout.builder(
                          mobile: (context) => Scaffold(
                            drawerScrimColor: Colors.transparent,
                            drawer: PublicationMode.isOn
                                ? null
                                : const AppSideBar(),
                            appBar: const MobileAppBar(),
                            body: panel,
                          ),
                          desktop: (context) => Column(
                            children: [
                              const AppTopBar(),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 16),
                                  child: panel,
                                ),
                              ),
                            ],
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

  /// Whether [state] is at a publication's root, where [PublicationHeader] takes the
  /// breadcrumb row's place.
  bool _atPublicationRoot(DriveDetailLoadSuccess state) =>
      publicationConfigOf(context)?.scopeRootFolderId ==
      state.folderInView.folder.id;

  void _foldPublicationHeader(bool folded) {
    if (folded == _publicationHeaderFolded) return;
    setState(() => _publicationHeaderFolded = folded);
  }

  /// [child] with the scrolling that folds a publication root's header: the list
  /// moving off its top, or the wheel turned over the header itself.
  Widget _foldsPublicationHeader(String folderId, Widget child) {
    if (!PublicationMode.isOn) return child;
    _publicationFolderShown(folderId);
    return _turnsPublicationHeader(
      NotificationListener<Notification>(
        onNotification: (notification) {
          final metrics = switch (notification) {
            ScrollNotification(:final metrics) => metrics,
            ScrollMetricsNotification(:final metrics) => metrics,
            _ => null,
          };
          if (metrics == null || metrics.axis != Axis.vertical) return false;
          _publicationListCanScroll = metrics.maxScrollExtent > 0;
          _publicationListAtTop = metrics.pixels <= 0;
          // Only a scroll that moved the list: the list growing as the
          // header folds reports new metrics, and must not unfold it again.
          if (notification is ScrollUpdateNotification &&
              (notification.scrollDelta ?? 0) != 0) {
            _foldPublicationHeader(metrics.pixels > 0);
          }
          return false;
        },
        child: child,
      ),
    );
  }

  /// A folder newly shown starts with its header unfolded. Called by
  /// whatever reads the fold first in a build, the header itself included.
  void _publicationFolderShown(String folderId) {
    if (_publicationHeaderFolderId == folderId) return;
    _publicationHeaderFolderId = folderId;
    _publicationHeaderFolded = false;
    _publicationListAtTop = true;
  }

  /// [child] where the wheel, or a swipe on a touch screen, folds a publication
  /// root's header down when the list has more to show and unfolds it up
  /// from the list's top. A swipe is the only way back on a phone whose list
  /// fits once the header has folded, and so never scrolls again.
  Widget _turnsPublicationHeader(Widget child) => Listener(
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent) return;
          if (event.scrollDelta.dy > 0 && _publicationListCanScroll) {
            _foldPublicationHeader(true);
          } else if (event.scrollDelta.dy < 0 && _publicationListAtTop) {
            _foldPublicationHeader(false);
          }
        },
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < 0 && _publicationListCanScroll) {
              _foldPublicationHeader(true);
            } else if (velocity > 0 && _publicationListAtTop) {
              _foldPublicationHeader(false);
            }
          },
          child: child,
        ),
      );

  /// A publication root's Download: the rows selected, or the whole publication.
  void _downloadFromPublicationHeader(DriveDetailLoadSuccess state) {
    final publication = publicationConfigOf(context)!;
    final selected = context.read<DriveDetailCubit>().selectedItems;
    if (state.multiselect && selected.isNotEmpty) {
      promptToDownloadMultipleFiles(
        context,
        selectedItems: selected,
        zipName: selected.length == 1 && selected.single is FolderDataTableItem
            ? selected.single.name
            : publication.title,
      );
      return;
    }
    promptToDownloadMultipleFiles(
      context,
      selectedItems: [
        DriveDataTableItemMapper.fromDrive(
            state.currentDrive, (_) => null, 0, true),
      ],
      zipName: publication.title,
    );
  }

  Widget _publicationHeader(
    DriveDetailLoadSuccess state, {
    required bool compact,
  }) {
    _publicationFolderShown(state.folderInView.folder.id);
    return _turnsPublicationHeader(PublicationHeader(
      coverHeight: compact ? 120 : 200,
      collapsed: _publicationHeaderFolded,
      compact: compact,
      downloadsSelection: state.multiselect &&
          context.read<DriveDetailCubit>().selectedItems.isNotEmpty,
      onDownload: () => _downloadFromPublicationHeader(state),
      onCopyLink: () =>
          copyPublicationLink(context, folderId: state.folderInView.folder.id),
    ));
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
                          if (_atPublicationRoot(driveDetailState)) ...[
                            _publicationHeader(driveDetailState,
                                compact: false),
                            const SizedBox(height: 24),
                          ] else ...[
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
                                    // A publication's crumbs start at the folder it
                                    // was published at, named by its title.
                                    rootFolderId: publicationConfigOf(context)
                                            ?.scopeRootFolderId ??
                                        driveDetailState
                                            .currentDrive.rootFolderId,
                                    path: driveDetailState.pathSegments,
                                    driveName:
                                        publicationConfigOf(context)?.title ??
                                            driveDetailState.currentDrive.name,
                                    isPrivate:
                                        driveDetailState.currentDrive.isPrivate,
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
                                          final publication =
                                              publicationConfigOf(context);
                                          zipName = publication != null &&
                                                  currentFolder.id ==
                                                      publication
                                                          .scopeRootFolderId
                                              ? publication.title
                                              : currentFolder.parentFolderId ==
                                                      null
                                                  ? driveDetail
                                                      .currentDrive.name
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
                                      child: _DriveMenu(
                                        builder: (context, isSyncing) =>
                                            ArDriveDropdown(
                                          anchor: const Aligned(
                                            follower: Alignment.topRight,
                                            target: Alignment.bottomRight,
                                          ),
                                          items: driveMenuItems(
                                            context,
                                            drive:
                                                driveDetailState.currentDrive,
                                            isOwner: isDriveOwner,
                                            isSynced: true,
                                            isSyncing: isSyncing,
                                            zipName:
                                                publicationConfigOf(context)
                                                    ?.title,
                                            onMoreInfo: () => context
                                                .read<DriveDetailCubit>()
                                                .selectDataItem(
                                                  DriveDataTableItemMapper
                                                      .fromDrive(
                                                    driveDetailState
                                                        .currentDrive,
                                                    (_) => null,
                                                    0,
                                                    isDriveOwner,
                                                  ),
                                                ),
                                          ),
                                          child: HoverWidget(
                                            child: ArDriveIcons.kebabMenu(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: explorerHeadingGap),
                          ],
                          if (hasFiles || hasSubfolders)
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _foldsPublicationHeader(
                                      driveDetailState.folderInView.folder.id,
                                      _buildDataList(
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
                                                folderName: driveDetailState
                                                    .folderInView.folder.name,
                                                contentsStillArriving:
                                                    driveDetailState
                                                        .contentsStillArriving,
                                                promptToAddFiles:
                                                    driveDetailState
                                                        .hasWritePermissions,
                                                isPrivate: driveDetailState
                                                    .currentDrive.isPrivate,
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
                                folderName:
                                    driveDetailState.folderInView.folder.name,
                                contentsStillArriving:
                                    driveDetailState.contentsStillArriving,
                                promptToAddFiles:
                                    driveDetailState.hasWritePermissions,
                                isPrivate:
                                    driveDetailState.currentDrive.isPrivate,
                                isRootFolder: driveDetailState.folderInView
                                            .folder.parentFolderId ==
                                        null &&
                                    !hasSubfolders,
                              ),
                            ),
                          // Room under the table, so a publication ends
                          // where its card visibly does, not at the window's
                          // edge.
                          if (PublicationMode.isOn) const SizedBox(height: 16),
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
          .colorTokens
          .primitives
          .transparent900_32,
      drawer: PublicationMode.isOn ? null : const AppSideBar(),
      appBar: MobileAppBar(
        showSearch: true,
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
          // A publication adds nothing to its drive: no New button. Not an
          // empty Container: given the whole height, it fills it, which hid
          // the file list for as long as it was there.
          if (state is! DriveDetailLoadSuccess || PublicationMode.isOn) {
            return const SizedBox.shrink();
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

    _onMobileFolderShown(state.folderInView.folder.id);

    final List<ArDriveDataTableItem> filteredItems;

    if (isShowingHiddenFiles) {
      filteredItems = items.toList();
    } else {
      filteredItems = items.where((item) => item.isHidden == false).toList();
    }

    return Column(
      children: [
        // A publication's root has its header in place of the folder bar.
        if (_atPublicationRoot(state))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _publicationHeader(state, compact: true),
          )
        else
          // The search field used to sit here, 16px of padding either side of it,
          // and did nothing until it was submitted - at which point it opened the
          // same sheet the bar's search icon now opens. Nothing was lost by
          // moving it; a 60px band above the file list was gained, on the layout
          // with the least height to spare. See [MobileAppBar.showSearch].
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Flexible(
                  child: MobileFolderNavigation(
                    driveName: publicationConfigOf(context)?.title ??
                        state.currentDrive.name,
                    isPrivate: state.currentDrive.isPrivate,
                    path: state.pathSegments,
                    isShowingHiddenFiles: isShowingHiddenFiles,
                  ),
                ),
              ],
            ),
          ),
        // The same warning the wide table carries. A phone reads a
        // half-walked drive exactly as a desktop does, and this is the
        // surface with the least room to work out for itself that a short
        // list is short because a sync is still running.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SyncingDriveNotice(driveId: state.currentDrive.id),
        ),
        Expanded(
          child: (hasSubfolders || hasFiles)
              ? _foldsPublicationHeader(
                  state.folderInView.folder.id,
                  ListView.separated(
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
                  ))
              : DriveDetailFolderEmptyCard(
                  promptToAddFiles: state.hasWritePermissions,
                  isPrivate: state.currentDrive.isPrivate,
                  driveId: state.currentDrive.id,
                  parentFolderId: state.folderInView.folder.id,
                  folderName: state.folderInView.folder.name,
                  contentsStillArriving: state.contentsStillArriving,
                  isRootFolder:
                      state.folderInView.folder.parentFolderId == null,
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
              child: dimIfHidden(
                  item.isHidden,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ArNSTitleWithChip(
                        title: Text(
                          item.name,
                          style:
                              ArDriveTypographyNew.of(context).paragraphNormal(
                            fontWeight: ArFontWeight.bold,
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colorTokens
                                .textHigh,
                          ),
                        ),
                        chip: item is FileDataTableItem
                            ? ArNSNameChip(
                                dataTxId: (item as FileDataTableItem).dataTxId,
                                hints:
                                    (item as FileDataTableItem).assignedNames ??
                                        const [],
                                isOwner: item.isOwner,
                              )
                            : const SizedBox.shrink(),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (item is FileDataTableItem) ...[
                            Text(
                              filesize(item.size),
                              style: ArDriveTypographyNew.of(context).caption(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colorTokens
                                    .textMid,
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: ArDriveTheme.of(context)
                                      .themeData
                                      .colorTokens
                                      .textMid,
                                ),
                                height: 3,
                                width: 3,
                              ),
                            )
                          ],
                          Flexible(
                            child: Text(
                              'Last updated: ${formatDate(item.lastUpdated)}',
                              style: ArDriveTypographyNew.of(context).caption(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colorTokens
                                    .textMid,
                              ),
                            ),
                          ),
                        ],
                      )
                    ],
                  )),
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
  final bool isPrivate;

  const MobileFolderNavigation({
    super.key,
    required this.path,
    required this.driveName,
    required this.isShowingHiddenFiles,
    required this.isPrivate,
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
                        child: Row(
                          children: [
                            // On every folder, not only the root: the name
                            // shown below the root is the folder's, so the
                            // lock is the only thing here that says whose.
                            if (isPrivate)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: PrivateDriveLock(),
                              ),
                            Expanded(
                              child: Text(
                                _pathToName(
                                  path.isEmpty ? driveName : path.last.text,
                                ),
                                // One line: the row is 45 high, and a second
                                // line was cut through the middle.
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ArDriveTypographyNew.of(context)
                                    .paragraphNormal(
                                        fontWeight: ArFontWeight.semiBold),
                              ),
                            ),
                          ],
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

                return _DriveMenu(
                  builder: (context, isSyncing) => ArDriveDropdown(
                    anchor: const Aligned(
                      follower: Alignment.topRight,
                      target: Alignment.bottomRight,
                    ),
                    items: driveMenuItems(
                      context,
                      drive: state.currentDrive,
                      isOwner: isOwner,
                      isSynced: true,
                      isSyncing: isSyncing,
                      zipName: publicationConfigOf(context)?.title,
                      onMoreInfo: () =>
                          context.read<DriveDetailCubit>().selectDataItem(
                                DriveDataTableItemMapper.fromDrive(
                                  state.currentDrive,
                                  (_) => null,
                                  0,
                                  isOwner,
                                ),
                              ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24.0,
                        vertical: 8,
                      ),
                      child: HoverWidget(
                        child: ArDriveIcons.kebabMenu(),
                      ),
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
        // A line rather than a glow: the glow was the text colour at 20%,
        // a white haze in dark mode.
        border: Border(
          top: BorderSide(
            color: ArDriveTheme.of(context).themeData.colorTokens.strokeLow,
          ),
        ),
        boxShadow: [
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
              backgroundColor: ArDriveTheme.of(context)
                  .themeData
                  .colorTokens
                  .buttonPrimaryDefault,
              child: ArDriveIcons.plus(
                color: ArDriveTheme.of(context)
                    .themeData
                    .colorTokens
                    .textOnPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rebuilds a drive menu when a sync starts or stops, so the items that start
/// one can say they are unavailable.
///
/// `SyncCubit` refuses a second sync outright - one at a time, no queue - and
/// an item that looks live, closes the menu and drops the request is the
/// present-and-inert failure this series keeps removing. The rebuild is scoped
/// to the menu rather than watched at the top of the page so a sync does not
/// rebuild the whole explorer.
class _DriveMenu extends StatelessWidget {
  const _DriveMenu({required this.builder});

  final Widget Function(BuildContext context, bool isSyncing) builder;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SyncCubit, SyncState>(
      buildWhen: (previous, current) =>
          (previous is SyncInProgress) != (current is SyncInProgress),
      builder: (context, state) => builder(context, state is SyncInProgress),
    );
  }
}
