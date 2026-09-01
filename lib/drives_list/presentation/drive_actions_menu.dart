import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:provider/provider.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/components/drive_detach_dialog.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/drive_share_dialog.dart';
import 'package:ardrive/components/hide_dialog.dart';
import 'package:ardrive/drives_list/presentation/drive_list_row.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The icon inside the tap target, which is [driveListMenuTapTarget] - a
/// layout constant, kept with the rest of the row's geometry.
const double _menuIconSize = 20;

/// The drive-wide actions, offered where the drives are listed.
///
/// Every item here calls the drive detail page's own implementation -
/// [promptToRenameDrive], [promptToShareDrive], [promptToToggleHideState],
/// [showDetachDriveDialog] and [SyncCubit.startSyncForDrive]. Nothing in this
/// file is a second implementation of any of them, and nothing in it opens a
/// second dialog: the same dialogs open, from the same functions, against the
/// same app-wide blocs.
///
/// "Info" is the one item that cannot act from here. The panel is
/// `DriveDetailCubit.selectDataItem`, which begins `this.state as
/// DriveDetailLoadSuccess`, and the cubit this page provides is built against
/// no drive at all - a different instance from the explorer's besides. Nor can
/// the panel simply be shown in a dialog: it is a side panel, returning a
/// `Flexible` around its own card for a full-height parent, and every attempt
/// to host it in one overflows.
///
/// So Info asks rather than acts. It records the request on the router - the
/// same one-shot mechanism a folder deep link uses - and opens the drive by
/// the road every other tap takes. The explorer's own cubit opens the panel
/// when it reports the drive loaded, which is where a side panel belongs and
/// where its Activity and Snapshots tabs work.
///
/// An action that does not apply is absent rather than disabled: renaming and
/// hiding belong to the owner, detaching belongs to somebody else's drive, and
/// hide and unhide are one item that says which of the two it is.
class DriveActionsMenu extends StatelessWidget {
  const DriveActionsMenu({
    super.key,
    required this.drive,
    required this.isOwner,
  });

  /// The drive as stored, not the row's view of it: [promptToShareDrive] and
  /// the hide dialog both take the record itself.
  final Drive drive;

  /// Whether this wallet owns the drive, which decides three of the items.
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    // The cubit refuses a second sync outright, so this item has to say so.
    // `isDisabled` as well as a null callback: [ArDriveDropdownItemTile] picks
    // its colours off the flag alone, and an item that looks live and does
    // nothing is the present-and-inert failure this series keeps removing.
    final isSyncing = context.watch<SyncCubit>().state is SyncInProgress;

    return ArDriveDropdown(
      // Without this the menu only ever opens downward, so on a phone the
      // rows a user scrolls to - the ones near the bottom - open their actions
      // off the end of the screen. ArDriveDropdown only flips when this
      // callback is supplied; the file explorer's row menu does the same.
      calculateVerticalAlignment: (isBelowHalfScreen) =>
          isBelowHalfScreen ? Alignment.bottomRight : Alignment.topRight,
      anchor: const Aligned(
        follower: Alignment.topRight,
        target: Alignment.bottomRight,
        // The button is at the row's trailing edge and the menu is wider than
        // the room left of it on a phone, so without this it opens past the
        // screen's left edge and takes every item's icon with it.
        shiftToWithinBound: AxisFlag(x: true),
      ),
      items: [
        ArDriveDropdownItem(
          // Nothing at all rather than a call that returns immediately.
          onClick: isSyncing
              ? null
              : () {
                  // Somebody pressed Sync, so it is theirs: the history has
                  // to say Manual, and the result is theirs to be told about.
                  // It ran as `background` to keep the old blocking modal off
                  // the list - but that modal is gone, and the summary that
                  // replaced it neither scrims nor takes a click, so the
                  // reason no longer holds and the record was simply wrong.
                  context.read<SyncCubit>().startSyncForDrive(
                        driveId: drive.id,
                      );
                },
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).syncThisDrive,
            isDisabled: isSyncing,
            icon: ArDriveIcons.refresh(size: _menuIconSize),
          ),
        ),
        if (isOwner)
          ArDriveDropdownItem(
            onClick: () => promptToRenameDrive(
              context,
              driveId: drive.id,
              driveName: drive.name,
            ),
            content: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).renameDrive,
              icon: ArDriveIcons.edit(size: _menuIconSize),
            ),
          ),
        ArDriveDropdownItem(
          onClick: () {
            // Order matters: the request has to be standing before the
            // selection reaches the explorer, or the drive loads with nothing
            // asked of it.
            context.read<AppRouterDelegate>().requestDriveInfo(drive.id);
            context.read<DrivesCubit>().selectDrive(drive.id);
          },
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).moreInfo,
            icon: ArDriveIcons.info(size: _menuIconSize),
          ),
        ),
        ArDriveDropdownItem(
          onClick: () => promptToShareDrive(context: context, drive: drive),
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).shareDrive,
            icon: ArDriveIcons.share(size: _menuIconSize),
          ),
        ),
        if (isOwner)
          ArDriveDropdownItem(
            onClick: () => promptToToggleHideState(
              context,
              item: DriveDataTableItemMapper.fromDrive(
                drive,
                (_) => null,
                0,
                isOwner,
              ),
            ),
            content: ArDriveDropdownItemTile(
              name: drive.isHidden
                  ? appLocalizationsOf(context).unhide
                  : appLocalizationsOf(context).hide,
              icon: drive.isHidden
                  ? ArDriveIcons.eyeOpen(size: _menuIconSize)
                  : ArDriveIcons.eyeClosed(size: _menuIconSize),
            ),
          ),
        if (!isOwner)
          ArDriveDropdownItem(
            onClick: () => showDetachDriveDialog(
              context: context,
              driveID: drive.id,
              driveName: drive.name,
            ),
            content: ArDriveDropdownItemTile(
              name: appLocalizationsOf(context).detachDriveAction,
              icon: ArDriveIcons.detach(size: _menuIconSize),
            ),
          ),
      ],
      child: ArDriveClickArea(
        tooltip: appLocalizationsOf(context).showMenu,
        child: Semantics(
          button: true,
          label: appLocalizationsOf(context).showMenu,
          child: SizedBox(
            width: driveListMenuTapTarget,
            height: driveListMenuTapTarget,
            child: Center(child: ArDriveIcons.kebabMenu(size: _menuIconSize)),
          ),
        ),
      ),
    );
  }
}
