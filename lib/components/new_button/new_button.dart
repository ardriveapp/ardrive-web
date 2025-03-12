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
import 'package:ardrive/pages/drive_detail/components/bulk_import_modal.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/dependency_injection.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_custom_event_properties.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/size_constants.dart';
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
          child: ArDriveFAB(
            onPressed: () {
              PlausibleEventTracker.trackNewButton(
                location: NewButtonLocation.sidebar,
              );
            },
            backgroundColor:
                ArDriveTheme.of(context).themeData.colors.themeAccentBrand,
            child: ArDriveIcons.plus(
              color: Colors.white,
            ),
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
        ArDriveNewButtonItem(
          onClick: () => attachDrive(context: context),
          name: appLocalizations.attachDrive,
          icon: ArDriveIcons.iconAttachDrive(size: defaultIconSize),
        ),
        if (driveDetailState is DriveDetailLoadSuccess && drive != null) ...[
          if (driveDetailState.currentDrive.privacy == 'public')
            ArDriveNewButtonItem(
              onClick: () {
                promptToCreateManifest(
                  context,
                  drive: drive!,
                  // TODO: for big drives, this might will be slow
                  hasPendingFiles: driveDetailState.currentFolderContents.any(
                    (element) =>
                        element.fileStatusFromTransactions ==
                        TransactionStatus.pending,
                  ),
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

  List<ArDriveNewButtonComponent> _getTopItems(BuildContext context) {
    final driveDetailState = context.read<DriveDetailCubit>().state;
    final drivesState = context.read<DrivesCubit>().state;
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
          ArDriveNewButtonItem(
            onClick: () {
              promptToUpload(
                context,
                driveId: drive!.id,
                parentFolderId: currentFolder!.folder.id,
                isFolderUpload: false,
              );
            },
            isDisabled: !driveDetailState.hasWritePermissions || !canUpload,
            name: appLocalizations.uploadFiles,
            icon: ArDriveIcons.iconUploadFiles(size: defaultIconSize),
          ),
          ArDriveNewButtonItem(
            onClick: () {
              promptToUpload(
                context,
                driveId: drive!.id,
                parentFolderId: currentFolder!.folder.id,
                isFolderUpload: true,
              );
            },
            isDisabled: !driveDetailState.hasWritePermissions || !canUpload,
            name: appLocalizations.uploadFolder,
            icon: ArDriveIcons.iconUploadFolder1(size: defaultIconSize),
          ),
          const ArDriveNewButtonDivider(),
        ],
        if (drivesState is DrivesLoadSuccess) ...[
          ArDriveNewButtonItem(
            onClick: () {
              promptToCreateDrive(context);
            },
            isDisabled: !drivesState.canCreateNewDrive || !canUpload,
            name: appLocalizations.newDrive,
            icon: ArDriveIcons.addDrive(size: defaultIconSize),
          ),
        ],
        if (driveDetailState is DriveDetailLoadSuccess && drive != null) ...[
          ArDriveNewButtonItem(
            onClick: () => promptToCreateFolder(
              context,
              driveId: driveDetailState.currentDrive.id,
              parentFolderId: currentFolder!.folder.id,
            ),
            isDisabled: !driveDetailState.hasWritePermissions || !canUpload,
            name: appLocalizations.newFolder,
            icon: ArDriveIcons.iconNewFolder1(size: defaultIconSize),
          ),
          if (drive != null)
            ArDriveNewButtonItem(
              name: appLocalizationsOf(context).newFilePin,
              icon: ArDriveIcons.pinWithCircle(size: defaultIconSize),
              onClick: () => showPinFileDialog(context: context),
              isDisabled:
                  !driveDetailState.hasWritePermissions || drive == null,
            ),
          const ArDriveNewButtonDivider(),
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

  List<ArDriveNewButtonComponent> _getPlusButtonItems(BuildContext context) {
    final driveDetailState = context.read<DriveDetailCubit>().state;
    final drivesState = context.read<DrivesCubit>().state;
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
          ArDriveNewButtonItem(
            onClick: () {
              promptToUpload(
                context,
                driveId: drive!.id,
                parentFolderId: currentFolder!.folder.id,
                isFolderUpload: false,
              );
            },
            isDisabled: !driveDetailState.hasWritePermissions || !canUpload,
            name: appLocalizations.uploadFiles,
            icon: ArDriveIcons.iconUploadFiles(size: defaultIconSize),
          ),
          ArDriveNewButtonItem(
            onClick: () {
              promptToUpload(
                context,
                driveId: drive!.id,
                parentFolderId: currentFolder!.folder.id,
                isFolderUpload: true,
              );
            },
            isDisabled: !driveDetailState.hasWritePermissions || !canUpload,
            name: appLocalizations.uploadFolder,
            icon: ArDriveIcons.iconUploadFolder1(size: defaultIconSize),
          ),
          if (driveDetailState.currentDrive.privacy == 'public')
            _getImportFromManifestItem(
              context,
              !driveDetailState.hasWritePermissions || !canUpload,
            ),
        ],
        const ArDriveNewButtonDivider(),
        if (drivesState is DrivesLoadSuccess) ...[
          ArDriveNewButtonItem(
            onClick: () {
              promptToCreateDrive(context);
            },
            isDisabled: !drivesState.canCreateNewDrive || !canUpload,
            name: appLocalizations.newDrive,
            icon: ArDriveIcons.addDrive(size: defaultIconSize),
          ),
        ],
        if (driveDetailState is DriveDetailLoadSuccess && drive != null) ...[
          ArDriveNewButtonItem(
            onClick: () => promptToCreateFolder(
              context,
              driveId: driveDetailState.currentDrive.id,
              parentFolderId: currentFolder!.folder.id,
            ),
            isDisabled: !driveDetailState.hasWritePermissions || !canUpload,
            name: appLocalizations.newFolder,
            icon: ArDriveIcons.iconNewFolder1(size: defaultIconSize),
          ),
          if (drive != null)
            ArDriveNewButtonItem(
              name: appLocalizationsOf(context).newFilePin,
              icon: ArDriveIcons.pinWithCircle(size: defaultIconSize),
              onClick: () => showPinFileDialog(context: context),
              isDisabled:
                  !driveDetailState.hasWritePermissions || drive == null,
            ),
          const ArDriveNewButtonDivider(),
        ],
        ArDriveNewButtonItem(
          iconAlignment: ArDriveArDriveDropdownItemTileIconAlignment.right,
          name: appLocalizationsOf(context).advanced,
          display: _getAdvancedItems(context).isNotEmpty,
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
