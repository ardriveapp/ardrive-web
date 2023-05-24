import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/create_manifest_form.dart';
import 'package:ardrive/components/create_shortcut_form.dart';
import 'package:ardrive/components/create_snapshot_dialog.dart';
import 'package:ardrive/components/drive_attach_form.dart';
import 'package:ardrive/components/drive_create_form.dart';
import 'package:ardrive/components/folder_create_form.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
    List<ArDriveNewButtonItem> items = _getItems(context);

    if (isBottomNavigationButton) {
      return ArDriveFAB(
          backgroundColor:
              ArDriveTheme.of(context).themeData.colors.themeAccentBrand,
          child: ArDriveIcons.plus(
            color: Colors.white,
          ),
          onPressed: () {
            final scrollController = ScrollController();

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
                      color: ArDriveTheme.of(context)
                          .themeData
                          .tableTheme
                          .backgroundColor,
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ArDriveScrollBar(
                        controller: scrollController,
                        alwaysVisible: true,
                        child: ListView(
                            controller: scrollController,
                            children: List.generate(items.length, (index) {
                              return Column(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.pop(context);
                                      items[index].onClick();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                        horizontal: 16,
                                      ),
                                      child: ArDriveDropdownItemTile(
                                        icon: items[index]
                                            .icon
                                            .copyWith(size: 24),
                                        name: items[index].name,
                                        isDisabled: items[index].isDisabled,
                                        fontStyle: ArDriveTypography.body
                                            .buttonLargeBold(),
                                      ),
                                    ),
                                  ),
                                  if (index != items.length - 1)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 24.0),
                                      child: Divider(
                                        height: 1,
                                        thickness: 1,
                                      ),
                                    ),
                                ],
                              );
                            })),
                      ),
                    ),
                  );
                });
          });
    }

    return ArDriveDropdown(
      width: dropdownWidth,
      anchor: anchor,
      items: _buildDriveDropdownItems(context),
      child: child ??
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ArDriveFAB(
              backgroundColor:
                  ArDriveTheme.of(context).themeData.colors.themeAccentBrand,
              child: ArDriveIcons.plus(
                color: Colors.white,
              ),
            ),
          ),
    );
  }

  List<ArDriveNewButtonItem> _getItems(BuildContext context) {
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
        if (drivesState is DrivesLoadSuccess) ...[
          ArDriveNewButtonItem(
            onClick: () {
              promptToCreateDrive(context);
            },
            isDisabled: !drivesState.canCreateNewDrive || !canUpload,
            name: appLocalizations.newDrive,
            icon: ArDriveIcons.addDrive(size: defaultIconSize),
          ),
          ArDriveNewButtonItem(
            onClick: () => attachDrive(context: context),
            name: appLocalizations.attachDrive,
            icon: ArDriveIcons.iconAttachDrive(size: defaultIconSize),
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
          ArDriveNewButtonItem(
            onClick: () => attachDrive(context: context),
            name: appLocalizations.attachDrive,
            icon: ArDriveIcons.iconAttachDrive(size: defaultIconSize),
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
        ],
        if (driveDetailState is DriveDetailLoadSuccess &&
            driveDetailState.currentDrive.privacy == 'public' &&
            drive != null) ...[
          ArDriveNewButtonItem(
            onClick: () {
              promptToCreateManifest(
                context,
                drive: drive!,
              );
            },
            isDisabled: driveDetailState.driveIsEmpty || !canUpload,
            name: appLocalizations.createManifest,
            icon: ArDriveIcons.tournament(size: defaultIconSize),
          ),
          ArDriveNewButtonItem(
            onClick: () {
              createShortcut(
                context: context,
                driveId: driveDetailState.currentDrive.id,
                folderInViewId: driveDetailState.folderInView.folder.id,
                folderInViewPath: driveDetailState.folderInView.folder.path,
              );
            },
            // isDisabled: !drivesState.canCreateNewDrive || !canUpload,
            name: 'Create Shortcut',
            icon: ArDriveIcons.addDrive(size: defaultIconSize),
          ),
        ],
        if (context.read<AppConfig>().enableQuickSyncAuthoring &&
            driveDetailState is DriveDetailLoadSuccess &&
            drive != null)
          ArDriveNewButtonItem(
            onClick: () {
              promptToCreateSnapshot(
                context,
                drive!,
              );
            },
            isDisabled: driveDetailState.driveIsEmpty ||
                !profile.hasMinimumBalanceForUpload(
                  minimumWalletBalance: minimumWalletBalance,
                ),
            name: appLocalizations.createSnapshot,
            icon: ArDriveIcons.iconCreateSnapshot(size: defaultIconSize),
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

  List<ArDriveDropdownItem> _buildDriveDropdownItems(BuildContext context) {
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
        if (drivesState is DrivesLoadSuccess) ...[
          _buildDriveDropdownItem(
            onClick: () {
              promptToCreateDrive(context);
            },
            isDisabled: !drivesState.canCreateNewDrive || !canUpload,
            name: appLocalizations.newDrive,
            icon: ArDriveIcons.addDrive(size: defaultIconSize),
          ),
          _buildDriveDropdownItem(
            onClick: () => attachDrive(context: context),
            name: appLocalizations.attachDrive,
            icon: ArDriveIcons.iconAttachDrive(size: defaultIconSize),
          ),
        ],
        if (driveDetailState is DriveDetailLoadSuccess && drive != null) ...[
          _buildDriveDropdownItem(
            onClick: () => createShortcut(
              context: context,
              driveId: driveDetailState.currentDrive.id,
              folderInViewId: driveDetailState.folderInView.folder.id,
              folderInViewPath: driveDetailState.folderInView.folder.path,
            ),
            name: 'Create Shortcut',
            icon: ArDriveIcons.iconAttachDrive(size: defaultIconSize),
          ),
          _buildDriveDropdownItem(
            onClick: () => promptToCreateFolder(
              context,
              driveId: driveDetailState.currentDrive.id,
              parentFolderId: currentFolder!.folder.id,
            ),
            isDisabled: !driveDetailState.hasWritePermissions || !canUpload,
            name: appLocalizations.newFolder,
            icon: ArDriveIcons.iconNewFolder1(size: defaultIconSize),
          ),
          _buildDriveDropdownItem(
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
          _buildDriveDropdownItem(
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
        ],
        if (driveDetailState is DriveDetailLoadSuccess &&
            driveDetailState.currentDrive.privacy == 'public' &&
            drive != null)
          _buildDriveDropdownItem(
            onClick: () {
              promptToCreateManifest(
                context,
                drive: drive!,
              );
            },
            isDisabled: driveDetailState.driveIsEmpty || !canUpload,
            name: appLocalizations.createManifest,
            icon: ArDriveIcons.tournament(size: defaultIconSize),
          ),
        if (context.read<AppConfig>().enableQuickSyncAuthoring &&
            driveDetailState is DriveDetailLoadSuccess &&
            drive != null)
          _buildDriveDropdownItem(
            onClick: () {
              promptToCreateSnapshot(
                context,
                drive!,
              );
            },
            isDisabled: driveDetailState.driveIsEmpty ||
                !profile.hasMinimumBalanceForUpload(
                  minimumWalletBalance: minimumWalletBalance,
                ),
            name: appLocalizations.createSnapshot,
            icon: ArDriveIcons.iconCreateSnapshot(size: defaultIconSize),
          ),
      ];
    } else {
      return [
        _buildDriveDropdownItem(
          onClick: () => attachDrive(context: context),
          name: appLocalizations.attachDrive,
          icon: ArDriveIcons.iconAttachDrive(size: defaultIconSize),
        ),
      ];
    }
  }
}

class ArDriveNewButtonItem {
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

ArDriveDropdownItem _buildDriveDropdownItem({
  required VoidCallback? onClick,
  required String name,
  required ArDriveIcon icon,
  bool isDisabled = false,
}) {
  return ArDriveDropdownItem(
    onClick: isDisabled ? null : onClick,
    content: ArDriveDropdownItemTile(
      name: name,
      icon: icon,
      isDisabled: isDisabled,
    ),
  );
}
