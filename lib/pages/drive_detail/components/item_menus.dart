import 'package:ardrive/arns/presentation/item/arns_item_names.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/create_snapshot_dialog.dart';
import 'package:ardrive/components/csv_export_dialog.dart';
import 'package:ardrive/components/drive_detach_dialog.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/fs_entry_license_form.dart';
import 'package:ardrive/components/hide_dialog.dart';
import 'package:ardrive/download/multiple_file_download_modal.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/publication/presentation/publication_chrome.dart';
import 'package:ardrive/publication/presentation/publish_to_web.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/presentation/full_resync_confirmation.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// One menu per kind of item, the same on every surface that offers it: a
// drive's row on Your drives, the explorer's drive header on desktop and on
// a phone, the unsynced drive's card, a folder's or a file's row, and the
// details panel's menu. Each surface used to build its own list, so one drive
// showed its actions in two orders and only one of them had Full resync
// (#2370). The order and the groups are the 27 October menus design.
//
// A surface passes what only it knows (how it shows More info, how it syncs);
// which items appear, in what order, and when, is decided here.

/// The groups joined by dividers, empty groups dropped.
List<ArDriveDropdownItem> menuWithDividers(
  List<List<ArDriveDropdownItem>> groups,
) {
  final items = <ArDriveDropdownItem>[];
  for (final group in groups.where((group) => group.isNotEmpty)) {
    if (items.isNotEmpty) items.add(const ArDriveDropdownItem.divider());
    items.addAll(group);
  }
  return items;
}

ArDriveDropdownItem _item(
  String name,
  ArDriveIcon icon, {
  required VoidCallback? onClick,
  double? height,
  bool isDisabled = false,
}) {
  return ArDriveDropdownItem(
    onClick: onClick,
    content: ArDriveDropdownItemTile(
      name: name,
      icon: icon,
      height: height,
      isDisabled: isDisabled,
    ),
  );
}

/// A drive's menu: share and publish; download and export; rename, snapshot
/// and hide; the two syncs; More info; detach.
///
/// [isSynced] is whether this device has the drive's contents. Until it does,
/// everything that reads them (publish, download, export, rename, snapshot,
/// full resync) is left out: a download of a drive never synced here was an
/// empty zip. [onMoreInfo] shows the drive's details the way the surface can,
/// and is null in the drive's own details; [onSync] replaces the plain sync
/// where the surface has its own.
List<ArDriveDropdownItem> driveMenuItems(
  BuildContext context, {
  required Drive drive,
  required bool isOwner,
  required bool isSynced,
  required bool isSyncing,
  required VoidCallback? onMoreInfo,
  VoidCallback? onSync,
  String? zipName,
  double? height,
}) {
  final strings = appLocalizationsOf(context);
  final publication = PublicationMode.isOn;
  ArDriveDataTableItem asItem() =>
      DriveDataTableItemMapper.fromDrive(drive, (_) => null, 0, isOwner);

  return menuWithDividers([
    [
      if (publication)
        _item(
          strings.copyLink,
          ArDriveIcons.copy(size: defaultIconSize),
          height: height,
          onClick: () =>
              copyPublicationLink(context, folderId: drive.rootFolderId),
        )
      else
        _item(
          strings.shareDrive,
          ArDriveIcons.share(size: defaultIconSize),
          height: height,
          onClick: () => promptToShareDrive(context: context, drive: drive),
        ),
      if (isSynced && offersPublishToWeb(context, drive))
        ArDriveDropdownItem(
          onClick: () => openPublishToWeb(context, drive: drive),
          content: PublishToWebMenuItem(
            drive: drive,
            iconSize: defaultIconSize,
            height: height,
          ),
        ),
    ],
    [
      if (isSynced)
        _item(
          strings.download,
          ArDriveIcons.download(size: defaultIconSize),
          height: height,
          onClick: () {
            final item = asItem();
            promptToDownloadMultipleFiles(
              context,
              selectedItems: [item],
              zipName: zipName ?? item.name,
            );
          },
        ),
      if (isSynced && !publication)
        _item(
          strings.exportDriveContents,
          ArDriveIcons.download(size: defaultIconSize),
          height: height,
          onClick: () =>
              promptToExportCSVData(context: context, driveId: drive.id),
        ),
    ],
    [
      if (isOwner && isSynced)
        _item(
          strings.renameDrive,
          ArDriveIcons.edit(size: defaultIconSize),
          height: height,
          onClick: () => promptToRenameDrive(
            context,
            driveId: drive.id,
            driveName: drive.name,
          ),
        ),
      if (isOwner && isSynced)
        _item(
          strings.createSnapshot,
          ArDriveIcons.iconCreateSnapshot(size: defaultIconSize),
          height: height,
          onClick: () => promptToCreateSnapshot(context, drive),
        ),
      if (isOwner)
        _item(
          drive.isHidden ? strings.unhide : strings.hide,
          drive.isHidden
              ? ArDriveIcons.eyeOpen(size: defaultIconSize)
              : ArDriveIcons.eyeClosed(size: defaultIconSize),
          height: height,
          onClick: () => promptToToggleHideState(context, item: asItem()),
        ),
    ],
    [
      // One sync at a time: the cubit refuses a second, so while one runs
      // both are shown unavailable rather than doing nothing.
      if (!publication)
        _item(
          strings.syncThisDrive,
          ArDriveIcons.refresh(size: defaultIconSize),
          height: height,
          isDisabled: isSyncing,
          onClick: isSyncing
              ? null
              : onSync ??
                  () => context
                      .read<SyncCubit>()
                      .startSyncForDrive(driveId: drive.id, deepSync: false),
        ),
      if (!publication && isSynced)
        _item(
          strings.deepSyncThisDrive,
          ArDriveIcons.cloudSync(size: defaultIconSize),
          height: height,
          isDisabled: isSyncing,
          onClick: isSyncing
              ? null
              : () async {
                  final syncCubit = context.read<SyncCubit>();
                  if (!await confirmFullResync(
                    context,
                    FullResyncScope.drive(drive.name),
                  )) {
                    return;
                  }
                  syncCubit.startSyncForDrive(
                    driveId: drive.id,
                    deepSync: true,
                  );
                },
        ),
    ],
    [
      // A publication is not its drive: the drive's details name it, list
      // its past names and ask GraphQL for its snapshots.
      if (!publication && onMoreInfo != null)
        _item(
          strings.moreInfo,
          ArDriveIcons.info(size: defaultIconSize),
          height: height,
          onClick: onMoreInfo,
        ),
    ],
    [
      // Read only here: a drive you own is never detached, and the profile
      // is only asked about one you don't.
      if (!isOwner && context.read<ProfileCubit>().state is ProfileLoggedIn)
        _item(
          strings.detachDriveAction,
          ArDriveIcons.detach(size: defaultIconSize),
          height: height,
          onClick: () => showDetachDriveDialog(
            context: context,
            driveID: drive.id,
            driveName: drive.name,
          ),
        ),
    ],
  ]);
}

/// A folder's menu: open; share and publish; download; rename, move,
/// license and hide; More info.
///
/// [drive] is null where the surface doesn't know it; share and publish need
/// it and are left out then. [onMoreInfo] is null where the menu sits in the
/// folder's own details.
List<ArDriveDropdownItem> folderMenuItems(
  BuildContext context, {
  required FolderDataTableItem folder,
  required Drive? drive,
  required String zipName,
  VoidCallback? onMoreInfo,
  double? height,
}) {
  final strings = appLocalizationsOf(context);
  final publication = PublicationMode.isOn;
  final isOwner = folder.isOwner;

  return menuWithDividers([
    [
      _item(
        strings.open,
        ArDriveIcons.folderOutline(size: defaultIconSize),
        height: height,
        onClick: () => context.read<DriveDetailCubit>().openDataItem(folder),
      ),
    ],
    [
      if (publication)
        _item(
          strings.copyLink,
          ArDriveIcons.copy(size: defaultIconSize),
          height: height,
          onClick: () => copyPublicationLink(context, folderId: folder.id),
        )
      // Not for a ghost folder: its metadata was never found, so a link
      // naming it points the recipient at nothing.
      else if (drive != null && !folder.isGhostFolder)
        _item(
          strings.shareFolder,
          ArDriveIcons.share(size: defaultIconSize),
          height: height,
          onClick: () => promptToShareDrive(
            context: context,
            drive: drive,
            folderId: folder.id,
            folderName: folder.name,
          ),
        ),
      if (drive != null &&
          !folder.isGhostFolder &&
          offersPublishToWeb(context, drive))
        ArDriveDropdownItem(
          onClick: () =>
              openPublishToWeb(context, drive: drive, folderId: folder.id),
          content: PublishToWebMenuItem(
            drive: drive,
            folderId: folder.id,
            iconSize: defaultIconSize,
            height: height,
          ),
        ),
    ],
    [
      _item(
        strings.download,
        ArDriveIcons.download(size: defaultIconSize),
        height: height,
        onClick: () => promptToDownloadMultipleFiles(
          context,
          selectedItems: [folder],
          zipName: zipName,
        ),
      ),
    ],
    [
      if (isOwner) ...[
        _item(
          strings.rename,
          ArDriveIcons.edit(size: defaultIconSize),
          height: height,
          onClick: () => promptToRenameModal(
            context,
            driveId: folder.driveId,
            folderId: folder.id,
            initialName: folder.name,
          ),
        ),
        _item(
          strings.move,
          ArDriveIcons.move(size: defaultIconSize),
          height: height,
          onClick: () => promptToMove(
            context,
            driveId: folder.driveId,
            selectedItems: [folder],
          ),
        ),
        _item(
          strings.addLicense,
          ArDriveIcons.license(size: defaultIconSize),
          height: height,
          onClick: () => promptToLicense(
            context,
            driveId: folder.driveId,
            selectedItems: [folder],
          ),
        ),
        hideFileDropdownItem(context, folder, height: height),
      ],
    ],
    [
      if (onMoreInfo != null)
        _item(
          strings.moreInfo,
          ArDriveIcons.info(size: defaultIconSize),
          height: height,
          onClick: onMoreInfo,
        ),
    ],
  ]);
}

/// A file's menu: preview; share and its names; download; rename (or edit,
/// for a note), move, license and hide; check status and More info.
///
/// [drive] is null where the surface doesn't know it. [onMoreInfo] is null
/// where the menu sits in the file's own details.
List<ArDriveDropdownItem> fileMenuItems(
  BuildContext context, {
  required FileDataTableItem file,
  required Drive? drive,
  VoidCallback? onMoreInfo,
  double? height,
}) {
  final strings = appLocalizationsOf(context);
  final publication = PublicationMode.isOn;
  final isOwner = file.isOwner;
  final isNote = file.contentType == 'text/markdown' ||
      file.contentType == 'text/x-markdown';

  return menuWithDividers([
    [
      if (drive?.isPublic ?? false)
        _item(
          strings.preview,
          ArDriveIcons.newWindow(size: defaultIconSize),
          height: height,
          onClick: () =>
              context.read<DriveDetailCubit>().launchPreview(file.dataTxId),
        ),
    ],
    [
      if (publication)
        _item(
          strings.copyLink,
          ArDriveIcons.copy(size: defaultIconSize),
          height: height,
          onClick: () => copyPublicationLink(
            context,
            folderId: file.parentFolderId,
            fileId: file.id,
          ),
        )
      else
        _item(
          strings.shareFile,
          ArDriveIcons.share(size: defaultIconSize),
          height: height,
          onClick: () => promptToShareFile(
            context: context,
            driveId: file.driveId,
            fileId: file.id,
          ),
        ),
      if (isOwner && drive != null)
        ...arnsItemMenuItems(
          context,
          item: file,
          drive: drive,
          height: height,
        ),
    ],
    [
      _item(
        strings.download,
        ArDriveIcons.download(size: defaultIconSize),
        height: height,
        onClick: () =>
            promptToDownloadProfileFile(context: context, file: file),
      ),
    ],
    [
      if (isOwner) ...[
        _item(
          isNote ? strings.editNote : strings.rename,
          ArDriveIcons.edit(size: defaultIconSize),
          height: height,
          onClick: () {
            if (isNote) {
              handleMarkdownFileEdit(context, file);
            } else {
              promptToRenameModal(
                context,
                driveId: file.driveId,
                fileId: file.id,
                initialName: file.name,
              );
            }
          },
        ),
        _item(
          strings.move,
          ArDriveIcons.move(size: defaultIconSize),
          height: height,
          onClick: () => promptToMove(
            context,
            driveId: file.driveId,
            selectedItems: [file],
          ),
        ),
        // A pinned file's data belongs to someone else, so it isn't ours to
        // license.
        if (file.pinnedDataOwnerAddress == null)
          _item(
            file.licenseTxId == null
                ? strings.addLicense
                : strings.updateLicense,
            ArDriveIcons.license(size: defaultIconSize),
            height: height,
            onClick: () => promptToLicense(
              context,
              driveId: file.driveId,
              selectedItems: [file],
            ),
          ),
        hideFileDropdownItem(context, file, height: height),
      ],
    ],
    [
      if (file.fileStatusFromTransactions == TransactionStatus.pending)
        checkUploadStatusDropdownItem(context, height: height),
      if (onMoreInfo != null)
        _item(
          strings.moreInfo,
          ArDriveIcons.info(size: defaultIconSize),
          height: height,
          onClick: onMoreInfo,
        ),
    ],
  ]);
}
