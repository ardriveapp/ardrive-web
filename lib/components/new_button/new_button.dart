import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/bulk_import/bulk_import_bloc.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/create_snapshot_dialog.dart';
import 'package:ardrive/components/pin_file_dialog.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/core/arfs/use_cases/bulk_import_files.dart';
import 'package:ardrive/core/arfs/use_cases/check_folder_conflicts.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/models/enums.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/pages/drive_detail/components/bulk_import_modal.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/upload_entry/domain/drive_wait.dart';
import 'package:ardrive/upload_entry/domain/upload_start.dart';
import 'package:ardrive/upload_entry/presentation/start_upload.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/dependency_injection.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_custom_event_properties.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../../manifests/data/repositories/manifest_repository_impl.dart';

class NewButton extends StatelessWidget {
  const NewButton({
    super.key,
    required this.drive,
    this.currentFolder,
    required this.driveDetailState,
    this.child,
    this.isBottomNavigationButton = false,
    this.anchor = const Aligned(
      follower: Alignment.bottomCenter,
      target: Alignment.topCenter,
    ),
    this.dropdownWidth = 208,
    this.customOffset,
  });

  final Drive? drive;
  final FolderWithContents? currentFolder;
  final DriveDetailState driveDetailState;
  final Widget? child;
  final Anchor anchor;
  final double dropdownWidth;
  final bool isBottomNavigationButton;
  final Offset? customOffset;

  @override
  Widget build(BuildContext context) {
    if (isBottomNavigationButton) {
      return _buildPlusButton(context);
    } else {
      return _buildNewButton(context);
    }
  }

  Widget _buildPlusButton(BuildContext context) {
    return ArDriveFAB(
        backgroundColor:
            ArDriveTheme.of(context).themeData.colors.themeAccentBrand,
        child: ArDriveIcons.plus(
          color: Colors.white,
        ),
        onPressed: () {
          final ScrollController scrollController = ScrollController();
          final List<ArDriveNewButtonComponent> items =
              _getPlusButtonItems(context);

          _displayPlusModal(context, scrollController, items);

          PlausibleEventTracker.trackNewButton(
            location: NewButtonLocation.bottom,
          );
        });
  }

  Widget _buildNewButton(BuildContext context) {
    final List<ArDriveSubmenuItem> menuItems = _getNewMenuItems(context);

    final subMenuChild = child ??
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _HoverableNewButton(
            tooltip: appLocalizationsOf(context).createNew,
            onPressed: () {
              PlausibleEventTracker.trackNewButton(
                location: NewButtonLocation.sidebar,
              );
            },
          ),
        );

    final offset = customOffset ?? const Offset(140, -40);

    return ScreenTypeLayout.builder(
      mobile: (_) => ArDriveSubmenu(
        onOpen: () {
          PlausibleEventTracker.trackNewButton(
            location: NewButtonLocation.sidebar,
          );
        },
        menuChildren: menuItems,
        child: subMenuChild,
      ),
      desktop: (_) => ArDriveSubmenu(
        onOpen: () {
          PlausibleEventTracker.trackNewButton(
            location: NewButtonLocation.sidebar,
          );
        },
        alignmentOffset: offset,
        menuChildren: menuItems,
        child: subMenuChild,
      ),
    );
  }

  void _displayPlusModal(
    BuildContext context,
    ScrollController scrollController,
    List<ArDriveNewButtonComponent> items,
  ) {
    showModalBottomSheet(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      context: context,
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(8),
          ),
          child: Container(
            color:
                ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
            padding: const EdgeInsets.only(bottom: 8),
            child: ArDriveScrollBar(
              controller: scrollController,
              alwaysVisible: true,
              child: ListView(
                shrinkWrap: true,
                controller: scrollController,
                children: List.generate(
                  items.length,
                  (index) {
                    final item = items[index];

                    if (item is ArDriveNewButtonItem) {
                      return item.display
                          ? Column(
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    if (!item.isDisabled) {
                                      Navigator.pop(context);
                                      item.onClick();
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 16,
                                    ),
                                    child: ArDriveHoverWidget(
                                      hoverColor: ArDriveTheme.of(context)
                                          .themeData
                                          .dropdownTheme
                                          .hoverColor,
                                      defaultColor: null,
                                      showMouseCursor: !item.isDisabled,
                                      child: ArDriveDropdownItemTile(
                                        iconAlignment: item.iconAlignment,
                                        icon: item.icon.copyWith(size: 24),
                                        name: item.name,
                                        isDisabled: item.isDisabled,
                                        fontStyle: ArDriveTypography.body
                                            .buttonLargeBold(),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox();
                    } else {
                      return Divider(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgSubtle,
                        height: 8,
                      );
                    }
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<ArDriveSubmenuItem> _getNewMenuItems(BuildContext context) {
    final List<ArDriveSubmenuItem> topLevelItems = [];
    final List<ArDriveNewButtonComponent> topItems = _getTopItems(context);

    topLevelItems.addAll(topItems.map(
      (topItem) {
        if (topItem is ArDriveNewButtonItem) {
          return _newButtonItemToSubMenuItem(context, topItem);
        } else /** it's an ArDriveNewButtonDivider */ {
          return ArDriveSubmenuItem(
            isDisabled: true,
            widget: Container(
              color: ArDriveTheme.of(context)
                  .themeData
                  .dropdownTheme
                  .backgroundColor,
              child: Column(
                children: [
                  Divider(
                    color:
                        ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
                    height: 8,
                  ),
                ],
              ),
            ),
          );
        }
      },
    ).toList());
    final advancedItems = _getAdvancedItems(context);

    // Advanced holds only what needs the drive's contents, so with no drive
    // open it is empty and never drawn. It used to hold attaching a drive as
    // well, which is why a menu with no drive open was one row opening onto
    // one action.
    if (advancedItems.isNotEmpty) {
      topLevelItems.add(
        ArDriveSubmenuItem(
          isDisabled: false,
          children: advancedItems
              .map(
                (advancedItem) => _newButtonItemToSubMenuItem(
                  context,
                  advancedItem,
                ),
              )
              .toList(),
          widget: ArDriveHoverWidget(
            hoverColor:
                ArDriveTheme.of(context).themeData.dropdownTheme.hoverColor,
            defaultColor: ArDriveTheme.of(context)
                .themeData
                .dropdownTheme
                .backgroundColor,
            showMouseCursor: true,
            child: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).advanced,
              icon: ArDriveIcons.carretRight(size: defaultIconSize),
              isDisabled: false,
              iconAlignment: ArDriveArDriveDropdownItemTileIconAlignment.right,
            ),
          ),
        ),
      );
    }

    return topLevelItems;
  }

  ArDriveSubmenuItem _newButtonItemToSubMenuItem(
    BuildContext context,
    ArDriveNewButtonItem item,
  ) {
    return ArDriveSubmenuItem(
      isDisabled: item.isDisabled,
      onClick: () {
        if (!item.isDisabled) {
          item.onClick();
        }
      },
      widget: ArDriveHoverWidget(
        hoverColor: ArDriveTheme.of(context).themeData.dropdownTheme.hoverColor,
        defaultColor:
            ArDriveTheme.of(context).themeData.dropdownTheme.backgroundColor,
        showMouseCursor: !item.isDisabled,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 24.0),
              child: ArDriveDropdownItemTile(
                icon: item.icon,
                name: item.name,
                isDisabled: item.isDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<ArDriveNewButtonItem> _getAdvancedItems(BuildContext context) {
    final driveDetailState = context.read<DriveDetailCubit>().state;
    final appLocalizations = appLocalizationsOf(context);
    final profileState = context.read<ProfileCubit>().state;
    final profile = profileState;
    final minimumWalletBalance = BigInt.from(10000000);

    if (profile is ProfileLoggedIn) {
      final canUpload = profile.canUpload(
        minimumWalletBalance: minimumWalletBalance,
      );

      return [
        if (driveDetailState is DriveDetailLoadSuccess && drive != null) ...[
          if (driveDetailState.currentDrive.privacy == 'public')
            ArDriveNewButtonItem(
              onClick: () {
                // wait 100 ms before creating manifest
                Future.delayed(
                  const Duration(milliseconds: 100),
                  () {
                    promptToCreateManifest(
                      context,
                      drive: drive!,
                      // TODO: for big drives, this might will be slow
                      hasPendingFiles:
                          driveDetailState.currentFolderContents.any(
                        (element) =>
                            element.fileStatusFromTransactions ==
                            TransactionStatus.pending,
                      ),
                    );
                  },
                );
              },
              isDisabled: !driveDetailState.hasWritePermissions ||
                  driveDetailState.driveIsEmpty ||
                  !canUpload,
              name: appLocalizations.createManifest,
              icon: ArDriveIcons.manifest(size: defaultIconSize),
            ),
          ArDriveNewButtonItem(
            onClick: () {
              promptToCreateSnapshot(
                context,
                drive!,
              );
            },
            isDisabled: !driveDetailState.hasWritePermissions ||
                driveDetailState.driveIsEmpty,
            name: appLocalizations.newSnapshot,
            icon: ArDriveIcons.iconCreateSnapshot(size: defaultIconSize),
          ),
          if (driveDetailState.currentDrive.privacy == 'public')
            _getImportFromManifestItem(
              context,
              !driveDetailState.hasWritePermissions || !canUpload,
            ),
        ]
      ];
    }

    return [];
  }

  /// Where Upload would lead from here: see [decideUploadStart].
  UploadStart _uploadStart(BuildContext context) {
    final router = context.read<AppRouterDelegate>();

    return decideUploadStart(
      detailState: context.read<DriveDetailCubit>().state,
      showingDrivesList: router.showingDrivesList,
      openDriveId: router.driveId,
      drivesState: context.read<DrivesCubit>().state,
    );
  }

  /// What the drive [driveId] is doing, the way every New action reads it.
  DriveWait _driveWait(BuildContext context, String driveId) {
    final syncCubit = context.read<SyncCubit>();

    return driveWait(
      driveId: driveId,
      detailState: context.read<DriveDetailCubit>().state,
      syncState: syncCubit.state,
      syncingDriveId: syncCubit.syncingDriveId,
      completedDriveIds: syncCubit.completedDriveIds,
      runDriveIds: syncCubit.syncingDriveIds,
    );
  }

  /// Upload File(s) and Upload Folder, offered to anybody logged in.
  ///
  /// Inside an open drive they go straight to the picker, as they always have.
  /// Everywhere else they go through [startUpload], which leads to the drive
  /// the files will go to. Leaving them out there was what made this menu
  /// read as broken: the one thing most people open it for was not in it.
  List<ArDriveNewButtonItem> _uploadItems(
    BuildContext context, {
    required bool canUpload,
  }) {
    final driveDetailState = context.read<DriveDetailCubit>().state;
    final appLocalizations = appLocalizationsOf(context);

    final bool isDisabled;
    if (driveDetailState is DriveDetailLoadSuccess && drive != null) {
      isDisabled = !driveDetailState.hasWritePermissions || !canUpload;
    } else if (driveDetailState is DriveDetailLoadUnsynced) {
      // Somebody else's drive is read-only whether or not it has synced, and
      // syncing it first would only lead to the same answer. A drive whose
      // sync found nothing on chain has no folder to upload into yet; its
      // card already says so and offers to look again.
      isDisabled = !isDriveOwner(
            context.read<ArDriveAuth>(),
            driveDetailState.drive.ownerAddress,
          ) ||
          !canUpload ||
          driveDetailState.syncFoundNothing;
    } else {
      // Greyed in the moment before the drive list is known, when there is
      // nowhere yet for it to lead.
      isDisabled = !canUpload || _uploadStart(context) is UploadNotYet;
    }

    void upload({required bool isFolderUpload}) {
      if (driveDetailState is DriveDetailLoadSuccess && drive != null) {
        promptToUpload(
          context,
          driveId: drive!.id,
          parentFolderId: currentFolder!.folder.id,
          isFolderUpload: isFolderUpload,
        );
      } else {
        startUpload(context, isFolderUpload: isFolderUpload);
      }
    }

    return [
      ArDriveNewButtonItem(
        onClick: () => upload(isFolderUpload: false),
        isDisabled: isDisabled,
        name: appLocalizations.uploadFiles,
        icon: ArDriveIcons.iconUploadFiles(size: defaultIconSize),
      ),
      ArDriveNewButtonItem(
        onClick: () => upload(isFolderUpload: true),
        isDisabled: isDisabled,
        name: appLocalizations.uploadFolder,
        icon: ArDriveIcons.iconUploadFolder1(size: defaultIconSize),
      ),
    ];
  }

  /// New Folder, New Note and New File Pin, for the drive in view.
  ///
  /// Offered whether or not that drive has been read, and while it opens or
  /// syncs, so the menu keeps one shape for as long as a drive is on screen.
  /// "Synced" is the app's language, not the reader's, and a menu that grows
  /// items when a sync finishes only teaches them it is unpredictable.
  ///
  /// Every press either acts or says why it cannot:
  ///
  /// - In an open drive, the action.
  /// - In a drive nothing has read, the same sync Upload starts, which the
  ///   page reports. Reading first is also what stops a second folder of the
  ///   same name being made, because that check reads local rows.
  /// - In a drive a sync is reading, a note that it is syncing.
  /// - In the second or two a drive takes to open, greyed.
  ///
  /// Nothing is remembered: see [DriveWait].
  ///
  /// Empty with no drive in view. On the drives list there is no folder for
  /// any of them to go into.
  List<ArDriveNewButtonComponent> _folderItems(
    BuildContext context, {
    required bool canUpload,
  }) {
    final driveDetailState = context.read<DriveDetailCubit>().state;
    final appLocalizations = appLocalizationsOf(context);

    final bool isDisabled;
    final bool pinIsDisabled;
    final void Function(VoidCallback action) whenRead;

    if (driveDetailState is DriveDetailLoadSuccess && drive != null) {
      isDisabled = !driveDetailState.hasWritePermissions || !canUpload;
      pinIsDisabled = !driveDetailState.hasWritePermissions;
      whenRead = (action) => action();
    } else if (driveDetailState is DriveDetailLoadUnsynced) {
      final readOnly = !isDriveOwner(
            context.read<ArDriveAuth>(),
            driveDetailState.drive.ownerAddress,
          ) ||
          driveDetailState.syncFoundNothing;

      isDisabled = readOnly || !canUpload;
      pinIsDisabled = readOnly;
      whenRead = (_) => readDriveForMenuAction(
            context,
            driveId: driveDetailState.drive.id,
          );
    } else if (_uploadStart(context) case UploadWhenOpen(:final driveId)) {
      // Upload leads here only while a drive is in view and opening.
      final syncing = _driveWait(context, driveId) == DriveWait.syncing;

      isDisabled = !syncing;
      pinIsDisabled = !syncing;
      whenRead = (_) => readDriveForMenuAction(context, driveId: driveId);
    } else {
      return const [];
    }

    return [
      ArDriveNewButtonItem(
        onClick: () => whenRead(
          () => promptToCreateFolder(
            context,
            driveId:
                (driveDetailState as DriveDetailLoadSuccess).currentDrive.id,
            parentFolderId: currentFolder!.folder.id,
          ),
        ),
        isDisabled: isDisabled,
        name: appLocalizations.newFolder,
        icon: ArDriveIcons.iconNewFolder1(size: defaultIconSize),
      ),
      ArDriveNewButtonItem(
        onClick: () => whenRead(
          () => promptToCreateNote(
            context,
            driveId:
                (driveDetailState as DriveDetailLoadSuccess).currentDrive.id,
            parentFolderId: currentFolder!.folder.id,
          ),
        ),
        isDisabled: isDisabled,
        name: appLocalizations.newNote,
        // TODO: Create dedicated note icon (document/text icon)
        icon: ArDriveIcons.edit(size: defaultIconSize),
      ),
      ArDriveNewButtonItem(
        name: appLocalizations.newFilePin,
        icon: ArDriveIcons.pinWithCircle(size: defaultIconSize),
        // The pin dialog reads the loaded drive straight off the cubit, so it
        // only ever runs once the drive is open. Not gated on the balance, as
        // it never was.
        onClick: () => whenRead(() => showPinFileDialog(context: context)),
        isDisabled: pinIsDisabled,
      ),
    ];
  }

  List<ArDriveNewButtonComponent> _getTopItems(BuildContext context) {
    final appLocalizations = appLocalizationsOf(context);
    final profileState = context.read<ProfileCubit>().state;
    final profile = profileState;
    final minimumWalletBalance = BigInt.from(10000000);

    if (profile is ProfileLoggedIn) {
      final canUpload = profile.canUpload(
        minimumWalletBalance: minimumWalletBalance,
      );

      final folderItems = _folderItems(context, canUpload: canUpload);

      return [
        // Everything that goes into the folder in view, then the drives
        // themselves. New Drive used to sit in the middle of the folder
        // actions, which is how a menu comes to read as a list of whatever
        // was added last.
        ..._uploadItems(context, canUpload: canUpload),
        ...folderItems,
        const ArDriveNewButtonDivider(),
        // Not gated on the drive list having loaded. Making a drive does not
        // depend on knowing which drives already exist, and that gate is what
        // left the All Drives menu holding nothing but an Advanced submenu.
        ArDriveNewButtonItem(
          onClick: () {
            promptToCreateDrive(context);
          },
          // Never greyed. A wallet that cannot pay is not a reason to withhold
          // the action: the dialog behind it says so and offers to top up,
          // which is more use than a dead control. It also matches the getting
          // started cards, which open the same dialog ungated.
          name: appLocalizations.newDrive,
          icon: ArDriveIcons.addDrive(size: defaultIconSize),
        ),
        ArDriveNewButtonItem(
          onClick: () => attachDrive(context: context),
          name: appLocalizations.attachDrive,
          icon: ArDriveIcons.iconAttachDrive(size: defaultIconSize),
        ),
        if (_getAdvancedItems(context).isNotEmpty)
          const ArDriveNewButtonDivider(),
      ];
    } else {
      return [
        ArDriveNewButtonItem(
          onClick: () => attachDrive(context: context),
          name: appLocalizations.attachDrive,
          icon: ArDriveIcons.iconAttachDrive(size: defaultIconSize),
        ),
      ];
    }
  }

  List<ArDriveNewButtonComponent> _getPlusButtonItems(BuildContext context) {
    final appLocalizations = appLocalizationsOf(context);
    final profileState = context.read<ProfileCubit>().state;
    final profile = profileState;
    final minimumWalletBalance = BigInt.from(10000000);

    if (profile is ProfileLoggedIn) {
      final canUpload = profile.canUpload(
        minimumWalletBalance: minimumWalletBalance,
      );

      final folderItems = _folderItems(context, canUpload: canUpload);

      return [
        // The same grouping as the sidebar menu: this folder, then drives,
        // then Advanced. Import from Manifest used to sit here as well as in
        // Advanced, so a public drive listed it twice.
        ..._uploadItems(context, canUpload: canUpload),
        ...folderItems,
        const ArDriveNewButtonDivider(),
        // Not gated on the drive list having loaded. Making a drive does not
        // depend on knowing which drives already exist, and that gate is what
        // left the All Drives menu holding nothing but an Advanced submenu.
        ArDriveNewButtonItem(
          onClick: () {
            promptToCreateDrive(context);
          },
          // Never greyed. A wallet that cannot pay is not a reason to withhold
          // the action: the dialog behind it says so and offers to top up,
          // which is more use than a dead control. It also matches the getting
          // started cards, which open the same dialog ungated.
          name: appLocalizations.newDrive,
          icon: ArDriveIcons.addDrive(size: defaultIconSize),
        ),
        ArDriveNewButtonItem(
          onClick: () => attachDrive(context: context),
          name: appLocalizations.attachDrive,
          icon: ArDriveIcons.iconAttachDrive(size: defaultIconSize),
        ),
        // Advanced holds only what needs the drive's contents now that
        // attaching one sits with the drive actions, so with no drive open it
        // is empty and this row is simply absent.
        if (_getAdvancedItems(context).isNotEmpty) ...[
          const ArDriveNewButtonDivider(),
          ArDriveNewButtonItem(
            iconAlignment: ArDriveArDriveDropdownItemTileIconAlignment.right,
            name: appLocalizationsOf(context).advanced,
            icon: ArDriveIcons.carretRight(size: defaultIconSize),
            isDisabled: false,
            onClick: () {
              _displayPlusModal(
                context,
                ScrollController(),
                _getAdvancedItems(context),
              );
            },
          ),
        ],
      ];
    } else {
      return [
        ArDriveNewButtonItem(
          onClick: () => attachDrive(context: context),
          name: appLocalizations.attachDrive,
          icon: ArDriveIcons.iconAttachDrive(size: defaultIconSize),
        ),
      ];
    }
  }

  ArDriveNewButtonItem _getImportFromManifestItem(
    BuildContext context,
    bool isDisabled,
  ) {
    return ArDriveNewButtonItem(
      onClick: () {
        showArDriveDialog(
          context,
          barrierDismissible: false,
          content: MultiRepositoryProvider(
            providers: setupBulkImportDependencies(context),
            child: BlocProvider(
              create: (context) => BulkImportBloc(
                  bulkImportFiles: context.read<BulkImportFiles>(),
                  ardriveAuth: context.read<ArDriveAuth>(),
                  checkFolderConflicts: CheckFolderConflicts(
                    context.read<FolderRepository>(),
                    context.read<FileRepository>(),
                  ),
                  manifestRepository: ManifestRepositoryImpl(
                    context.read<ArweaveService>(),
                    DownloadService(context.read<ArweaveService>()),
                  )),
              child: BulkImportModal(
                driveId: drive!.id,
                parentFolderId: currentFolder!.folder.id,
              ),
            ),
          ),
        );
      },
      isDisabled: isDisabled,
      name: 'Import from Manifest',
      icon: ArDriveIcons.manifest(size: defaultIconSize),
    );
  }
}

abstract class ArDriveNewButtonComponent {
  const ArDriveNewButtonComponent();
}

class ArDriveNewButtonItem extends ArDriveNewButtonComponent {
  const ArDriveNewButtonItem({
    required this.name,
    required this.icon,
    required this.onClick,
    this.isDisabled = false,
    this.iconAlignment = ArDriveArDriveDropdownItemTileIconAlignment.left,
    this.display = true,
  });

  final String name;
  final ArDriveIcon icon;
  final VoidCallback onClick;
  final bool isDisabled;
  final ArDriveArDriveDropdownItemTileIconAlignment iconAlignment;
  final bool display;
}

class ArDriveNewButtonDivider extends ArDriveNewButtonComponent {
  const ArDriveNewButtonDivider();
}

/// A hoverable FAB for the New button with visible hover effect.
class _HoverableNewButton extends StatefulWidget {
  final String tooltip;
  final VoidCallback onPressed;

  const _HoverableNewButton({
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_HoverableNewButton> createState() => _HoverableNewButtonState();
}

class _HoverableNewButtonState extends State<_HoverableNewButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final baseColor =
        ArDriveTheme.of(context).themeData.colors.themeAccentBrand;
    final hoverColor = Color.lerp(baseColor, Colors.black, 0.15)!;

    return ArDriveTooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: _isHovering ? hoverColor : baseColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isHovering ? 0.3 : 0.2),
                blurRadius: _isHovering ? 8 : 6,
                offset: Offset(0, _isHovering ? 4 : 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              customBorder: const CircleBorder(),
              child: Center(
                child: ArDriveIcons.plus(
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
