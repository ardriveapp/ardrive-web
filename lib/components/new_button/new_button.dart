import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/create_manifest_form.dart';
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
    this.anchor = const Aligned(
      follower: Alignment.bottomCenter,
      target: Alignment.topCenter,
    ),
    this.dropdownWidth = 275,
  });

  final Drive? drive;
  final FolderWithContents? currentFolder;
  final DriveDetailState driveDetailState;
  final Widget? child;
  final Anchor anchor;
  final double dropdownWidth;

  @override
  Widget build(BuildContext context) {
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
            icon: ArDriveIcons.drive(size: 24),
          ),
          _buildDriveDropdownItem(
            onClick: () => attachDrive(context: context),
            name: appLocalizations.attachDrive,
            icon: ArDriveIcons.drive(size: 24),
          ),
        ],
        if (driveDetailState is DriveDetailLoadSuccess && drive != null) ...[
          _buildDriveDropdownItem(
            onClick: () => promptToCreateFolder(
              context,
              driveId: driveDetailState.currentDrive.id,
              parentFolderId: currentFolder!.folder.id,
            ),
            isDisabled: !driveDetailState.hasWritePermissions || !canUpload,
            name: appLocalizations.newFolder,
            icon: ArDriveIcons.folderAdd(size: 24),
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
            icon: ArDriveIcons.folderAdd(size: 24),
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
            icon: ArDriveIcons.uploadCloud(size: 24),
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
            icon: ArDriveIcons.manifest(size: 24),
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
            icon: ArDriveIcons.camera(size: 24),
          ),
      ];
    } else {
      return [
        _buildDriveDropdownItem(
          onClick: () => attachDrive(context: context),
          name: appLocalizations.attachDrive,
          icon: ArDriveIcons.drive(size: 24),
        ),
      ];
    }
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
}
