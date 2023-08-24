import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/create_manifest_form.dart';
import 'package:ardrive/components/create_snapshot_dialog.dart';
import 'package:ardrive/components/drive_attach_form.dart';
import 'package:ardrive/components/drive_create_form.dart';
import 'package:ardrive/components/folder_create_form.dart';
import 'package:ardrive/components/pin_file_dialog.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

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
  });

  final Drive? drive;
  final FolderWithContents? currentFolder;
  final DriveDetailState driveDetailState;
  final Widget? child;
  final Anchor anchor;
  final double dropdownWidth;
  final bool isBottomNavigationButton;

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
        });
  }

  Widget _buildNewButton(BuildContext context) {
    final List<ArDriveSubmenuItem> menuItems = _getNewMenuItems(context);

    final theChild = child ??
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ArDriveFAB(
            backgroundColor:
                ArDriveTheme.of(context).themeData.colors.themeAccentBrand,
            child: ArDriveIcons.plus(
              color: Colors.white,
            ),
          ),
        );

    return ScreenTypeLayout.builder(
      mobile: (_) => ArDriveSubmenu(menuChildren: menuItems, child: theChild),
      desktop: (_) => ArDriveSubmenu(
        alignmentOffset: const Offset(140, -40),
        menuChildren: menuItems,
        child: theChild,
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
                    controller: scrollController,
                    children: List.generate(items.length, (index) {
                      final item = items[index];

                      if (item is ArDriveNewButtonItem) {
                        return Column(
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
                                child: ArDriveDropdownItemTile(
                                  icon: item.icon.copyWith(size: 24),
                                  name: item.name,
                                  isDisabled: item.isDisabled,
                                  fontStyle:
                                      ArDriveTypography.body.buttonLargeBold(),
                                ),
                              ),
                            ),
                          ],
                        );
                      } else {
                        return const Divider(
                          height: 8,
                        );
                      }
                    })),
              ),
            ),
          );
        });
  }

  List<ArDriveSubmenuItem> _getNewMenuItems(BuildContext context) {
    final List<ArDriveSubmenuItem> topLevelItems = [];

    final topItems = _getTopItems(context);

    topLevelItems.addAll(topItems.map(
      (e) {
        if (e is ArDriveNewButtonItem) {
          return ArDriveSubmenuItem(
            onClick: e.onClick,
            widget: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 24.0),
                  child: ArDriveDropdownItemTile(
                    icon: e.icon,
                    name: e.name,
                    isDisabled: e.isDisabled,
                  ),
                ),
              ],
            ),
          );
        } else /** it's an ArDriveNewButtonDivider */ {
          return ArDriveSubmenuItem(
            widget: const Column(
              children: [
                Divider(
                  height: 8,
                ),
              ],
            ),
          );
        }
      },
    ).toList());
    final advancedItems = _getAdvancedItems(context);
    if (advancedItems.isNotEmpty) {
      topLevelItems.add(
        ArDriveSubmenuItem(
          children: advancedItems
              .map((e) => ArDriveSubmenuItem(
                    onClick: e.onClick,
                    widget: ArDriveDropdownItemTile(
                      icon: e.icon,
                      name: e.name,
                      isDisabled: e.isDisabled,
                    ),
                  ))
              .toList(),
          widget: ArDriveDropdownItemTile(
            name: 'Advanced',
            icon: ArDriveIcons.carretRight(size: defaultIconSize),
            isDisabled: false,
            iconAlignment: ArDriveArDriveDropdownItemTileIconAlignment.right,
          ),
        ),
      );
    }

    return topLevelItems;
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
          ArDriveNewButtonItem(
            onClick: () => attachDrive(context: context),
            name: appLocalizations.attachDrive,
            icon: ArDriveIcons.iconAttachDrive(size: defaultIconSize),
          ),
          if (driveDetailState.currentDrive.privacy == 'public' &&
              drive != null)
            ArDriveNewButtonItem(
              onClick: () {
                promptToCreateManifest(
                  context,
                  drive: drive!,
                );
              },
              isDisabled: !driveDetailState.hasWritePermissions ||
                  driveDetailState.driveIsEmpty ||
                  !canUpload,
              name: appLocalizations.createManifest,
              icon: ArDriveIcons.tournament(size: defaultIconSize),
            ),
          if (context.read<ConfigService>().config.enableQuickSyncAuthoring &&
              drive != null)
            ArDriveNewButtonItem(
              onClick: () {
                promptToCreateSnapshot(
                  context,
                  drive!,
                );
              },
              isDisabled: !driveDetailState.hasWritePermissions ||
                  driveDetailState.driveIsEmpty ||
                  !profile.hasMinimumBalanceForUpload(
                    minimumWalletBalance: minimumWalletBalance,
                  ),
              name: appLocalizations.createSnapshot,
              icon: ArDriveIcons.iconCreateSnapshot(size: defaultIconSize),
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
            onClick: () => promptToUpload(
              context,
              driveId: drive!.id,
              parentFolderId: currentFolder!.folder.id,
              isFolderUpload: true,
            ),
            isDisabled: !driveDetailState.hasWritePermissions || !canUpload,
            name: appLocalizations.uploadFolder,
            icon: ArDriveIcons.iconUploadFolder1(size: defaultIconSize),
          ),
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
          if (context.read<ConfigService>().config.enablePins &&
              drive != null &&
              drive?.privacy == 'public')
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
            onClick: () => promptToUpload(
              context,
              driveId: drive!.id,
              parentFolderId: currentFolder!.folder.id,
              isFolderUpload: true,
            ),
            isDisabled: !driveDetailState.hasWritePermissions || !canUpload,
            name: appLocalizations.uploadFolder,
            icon: ArDriveIcons.iconUploadFolder1(size: defaultIconSize),
          ),
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
          if (context.read<ConfigService>().config.enablePins &&
              drive != null &&
              drive?.privacy == 'public')
            ArDriveNewButtonItem(
              name: appLocalizationsOf(context).newFilePin,
              icon: ArDriveIcons.pinWithCircle(size: defaultIconSize),
              onClick: () => showPinFileDialog(context: context),
              isDisabled:
                  !driveDetailState.hasWritePermissions || drive == null,
            ),
        ],
        const ArDriveNewButtonDivider(),
        ArDriveNewButtonItem(
          name: 'Advanced',
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
  });

  final String name;
  final ArDriveIcon icon;
  final VoidCallback onClick;
  final bool isDisabled;
}

class ArDriveNewButtonDivider extends ArDriveNewButtonComponent {
  const ArDriveNewButtonDivider();
}
