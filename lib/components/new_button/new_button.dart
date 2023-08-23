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

class NewButton extends StatelessWidget {
  const NewButton({
    super.key,
    required this.drive,
    this.currentFolder,
    required this.driveDetailState,
    required this.child,
    this.isBottomNavigationButton = false,
    this.anchor = const Aligned(
      follower: Alignment.bottomRight,
      target: Alignment.topRight, // Top Right
    ),
    this.dropdownWidth = 208,
  });

  final Drive? drive;
  final FolderWithContents? currentFolder;
  final DriveDetailState driveDetailState;
  final Widget child;
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
                              final item = items[index];
                              final isLastItem = index == items.length - 1;

                              return Column(
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onTap: () {
                                      if (!item.isDisabled) {
                                        Navigator.pop(context);
                                        item.onClick?.call();
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
                                        fontStyle: ArDriveTypography.body
                                            .buttonLargeBold(),
                                      ),
                                    ),
                                  ),
                                  if (!isLastItem)
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

    return ArDriveTreeDropdown(
      width: dropdownWidth,
      anchor: anchor,
      rootNode: _buildDropdownTree(context),
      // nestedPortal: nestedPortal,
      child: child,
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
            driveDetailState is DriveDetailLoadSuccess &&
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
        if (context.read<ConfigService>().config.enablePins &&
            driveDetailState is DriveDetailLoadSuccess &&
            drive != null &&
            drive?.privacy == 'public')
          ArDriveNewButtonItem(
            name: appLocalizationsOf(context).newFilePin,
            icon: ArDriveIcons.pinWithCircle(size: defaultIconSize),
            onClick: () => showPinFileDialog(context: context),
            isDisabled: !driveDetailState.hasWritePermissions || drive == null,
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

  TreeDropdownNode _buildDropdownTree(
    BuildContext context,
  ) {
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

      return TreeDropdownNode(
        id: '',
        content: child,
        children: [
          if (drivesState is DrivesLoadSuccess) ...[
            TreeDropdownNode(
              id: 'newDrive',
              isDisabled: !drivesState.canCreateNewDrive || !canUpload,
              onClick: () {
                promptToCreateDrive(context);
              },
              content: ArDriveDropdownItemTile(
                name: appLocalizations.newDrive,
                icon: ArDriveIcons.addDrive(size: defaultIconSize),
              ),
            ),
            TreeDropdownNode(
              id: 'attachDrive',
              onClick: () => attachDrive(context: context),
              content: ArDriveDropdownItemTile(
                name: appLocalizations.attachDrive,
                icon: ArDriveIcons.iconAttachDrive(size: defaultIconSize),
              ),
            ),
          ],
          if (driveDetailState is DriveDetailLoadSuccess && drive != null) ...[
            TreeDropdownNode(
              id: 'newFolder',
              isDisabled: !driveDetailState.hasWritePermissions || !canUpload,
              onClick: () => promptToCreateFolder(
                context,
                driveId: driveDetailState.currentDrive.id,
                parentFolderId: currentFolder!.folder.id,
              ),
              content: ArDriveDropdownItemTile(
                name: appLocalizations.newFolder,
                icon: ArDriveIcons.iconNewFolder1(size: defaultIconSize),
              ),
            ),
            TreeDropdownNode(
              id: 'uploadFolder',
              isDisabled: !driveDetailState.hasWritePermissions || !canUpload,
              onClick: () => promptToUpload(
                context,
                driveId: drive!.id,
                parentFolderId: currentFolder!.folder.id,
                isFolderUpload: true,
              ),
              content: ArDriveDropdownItemTile(
                name: appLocalizations.uploadFolder,
                icon: ArDriveIcons.iconUploadFolder1(size: defaultIconSize),
              ),
            ),
            TreeDropdownNode(
              id: 'uploadFiles',
              isDisabled: !driveDetailState.hasWritePermissions || !canUpload,
              onClick: () {
                promptToUpload(
                  context,
                  driveId: drive!.id,
                  parentFolderId: currentFolder!.folder.id,
                  isFolderUpload: false,
                );
              },
              content: ArDriveDropdownItemTile(
                name: appLocalizations.uploadFiles,
                icon: ArDriveIcons.iconUploadFiles(size: defaultIconSize),
              ),
            ),
          ],
          if (driveDetailState is DriveDetailLoadSuccess &&
              driveDetailState.currentDrive.privacy == 'public' &&
              drive != null)
            TreeDropdownNode(
              id: 'createManifest',
              isDisabled: driveDetailState.driveIsEmpty || !canUpload,
              onClick: () {
                promptToCreateManifest(
                  context,
                  drive: drive!,
                );
              },
              content: ArDriveDropdownItemTile(
                name: appLocalizations.createManifest,
                icon: ArDriveIcons.tournament(size: defaultIconSize),
              ),
            ),
          if (context.read<ConfigService>().config.enableQuickSyncAuthoring &&
              driveDetailState is DriveDetailLoadSuccess &&
              drive != null)
            TreeDropdownNode(
              id: 'createSnapshot',
              isDisabled: !driveDetailState.hasWritePermissions ||
                  driveDetailState.driveIsEmpty ||
                  !profile.hasMinimumBalanceForUpload(
                    minimumWalletBalance: minimumWalletBalance,
                  ),
              onClick: () {
                promptToCreateSnapshot(
                  context,
                  drive!,
                );
              },
              content: ArDriveDropdownItemTile(
                name: appLocalizations.createSnapshot,
                icon: ArDriveIcons.iconCreateSnapshot(size: defaultIconSize),
              ),
            ),
          // TODO: add pins
          TreeDropdownNode(
            id: 'MOAR',
            content: ArDriveDropdownItemTile(
              name: 'MOAR...',
              icon: ArDriveIcons.arrowRightOutline(),
            ),
            children: [
              TreeDropdownNode(
                id: 'Alpargata',
                content: ArDriveDropdownItemTile(
                  name: 'Alpargata',
                  icon: ArDriveIcons.question(),
                ),
              ),
              TreeDropdownNode(
                id: 'Chorizo',
                content: ArDriveDropdownItemTile(
                  name: 'Chorizo',
                  icon: ArDriveIcons.question(),
                ),
              ),
              TreeDropdownNode(
                id: 'Bicicleta',
                content: ArDriveDropdownItemTile(
                  name: 'Bicicleta',
                  icon: ArDriveIcons.question(),
                ),
              ),
              TreeDropdownNode(
                id: 'Metal',
                content: ArDriveDropdownItemTile(
                  name: 'Metal',
                  icon: ArDriveIcons.question(),
                ),
              ),
            ],
          )
        ],
      );
    } else {
      return TreeDropdownNode(
        id: 'attachDrive',
        onClick: () => attachDrive(context: context),
        content: ArDriveDropdownItemTile(
          name: appLocalizations.attachDrive,
          icon: ArDriveIcons.iconAttachDrive(size: defaultIconSize),
        ),
      );
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
  final VoidCallback? onClick;
  final bool isDisabled;
}
