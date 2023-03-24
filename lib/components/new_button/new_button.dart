import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
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
  });

  final Drive drive;
  final FolderWithContents? currentFolder;
  final DriveDetailState driveDetailState;

  @override
  Widget build(BuildContext context) {
    return ArDriveDropdown(
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
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).newDrive,
            icon: ArDriveIcons.drive(size: 24),
          ),
        ),
        ArDriveDropdownItem(
          onClick: () => attachDrive(context: context),
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).attachDrive,
            icon: ArDriveIcons.drive(size: 24),
          ),
        ),
        if (driveDetailState is DriveDetailLoadSuccess) ...[
          ArDriveDropdownItem(
            onClick: () => promptToCreateFolder(
              context,
              driveId: drive.id,
              parentFolderId: currentFolder!.folder.id,
            ),
            content: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).newFolder,
              icon: ArDriveIcons.folderAdd(size: 24),
            ),
          ),
          ArDriveDropdownItem(
            onClick: () => promptToUpload(
              context,
              driveId: drive.id,
              parentFolderId: currentFolder!.folder.id,
              isFolderUpload: true,
            ),
            content: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).uploadFolder,
              icon: ArDriveIcons.folderAdd(size: 24),
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
            content: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).uploadFiles,
              icon: ArDriveIcons.uploadCloud(size: 24),
            ),
          ),
        ],
        if (driveDetailState is DriveDetailLoadSuccess &&
            (driveDetailState as DriveDetailLoadSuccess).currentDrive.privacy ==
                'public')
          ArDriveDropdownItem(
            onClick: () {
              promptToCreateManifest(
                context,
                drive: drive,
              );
            },
            content: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).createManifest,
              icon: ArDriveIcons.manifest(size: 24),
            ),
          ),
        if (context.read<AppConfig>().enableQuickSyncAuthoring &&
            driveDetailState is DriveDetailLoadSuccess)
          ArDriveDropdownItem(
            onClick: () {
              promptToCreateSnapshot(
                context,
                drive,
              );
            },
            content: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).createSnapshot,
              icon: ArDriveIcons.camera(size: 24),
            ),
          ),
      ],
      child: Padding(
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
}
