import 'package:ardrive/authentication/components/breakpoint_layout_builder.dart';
import 'package:ardrive/components/list_page/list_table.dart';
import 'package:ardrive/pages/drive_detail/components/item_menus.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:provider/provider.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/components/drive_detach_dialog.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/drive_share_dialog.dart';
import 'package:ardrive/components/hide_dialog.dart';
import 'package:ardrive/drives_list/presentation/drive_list_row.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The icon inside the tap target, which is [driveListMenuTapTarget] - a
/// layout constant, kept with the rest of the row's geometry.
const double _menuIconSize = 20;

/// How far the menu button's target sits in from the row's end: it is
/// centred in the gutter the row reserves for it.
const double _targetInset = (listMenuGutter - driveListMenuTapTarget) / 2;

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
/// The items, their order and when each appears are the drive's one menu,
/// [driveMenuItems], the same as in the explorer. An action that does not
/// apply is absent rather than disabled.
class DriveActionsMenu extends StatelessWidget {
  const DriveActionsMenu({
    super.key,
    required this.drive,
    required this.isOwner,
    required this.isSynced,
    this.onShowDetails,
  });

  /// Opens the drive's details beside the list, where the page has a panel
  /// for them (desktop). Null on a phone, where More info opens the drive.
  final void Function(String driveId)? onShowDetails;

  /// The drive as stored, not the row's view of it: [promptToShareDrive] and
  /// the hide dialog both take the record itself.
  final Drive drive;

  /// Whether this wallet owns the drive, which decides three of the items.
  final bool isOwner;

  /// Whether this device has the drive's contents. Until it does, the menu
  /// leaves out what reads them, as the drive's other menus do.
  final bool isSynced;

  /// More info, the way this page can show it.
  ///
  /// On desktop the list's own details panel, for this row, without leaving
  /// the page. On a phone the drive opens with its details asked for, which
  /// the explorer honours once the drive has loaded; a drive not synced on
  /// this device never loads, so the request lingered and opened the panel by
  /// itself days later. There it is left out.
  VoidCallback? _moreInfo(BuildContext context) {
    final onShowDetails = this.onShowDetails;
    if (onShowDetails != null) {
      return () => onShowDetails(drive.id);
    }

    if (!isSynced) {
      return null;
    }

    return () {
      // Order matters: the request has to be standing before the selection
      // reaches the explorer, or the drive loads with nothing asked of it.
      context.read<AppRouterDelegate>().requestDriveInfo(drive.id);
      context.read<DrivesCubit>().selectDrive(drive.id);
    };
  }

  @override
  Widget build(BuildContext context) {
    // The cubit refuses a second sync outright, so this item has to say so.
    // `isDisabled` as well as a null callback: [ArDriveDropdownItemTile] picks
    // its colours off the flag alone, and an item that looks live and does
    // nothing is the present-and-inert failure this series keeps removing.
    //
    // Unavailable while the drive list refreshes too, as the page's own Sync
    // is, so the page gives one answer to "can I sync now?".
    final isSyncing = driveSyncUnavailable(context.watch<SyncCubit>().state);

    return ArDriveDropdown(
      // Without this the menu only ever opens downward, so on a phone the
      // rows a user scrolls to - the ones near the bottom - open their actions
      // off the end of the screen. ArDriveDropdown only flips when this
      // callback is supplied; the file explorer's row menu does the same.
      calculateVerticalAlignment: (isBelowHalfScreen) =>
          isBelowHalfScreen ? Alignment.bottomRight : Alignment.topRight,
      anchor: Aligned(
        follower: Alignment.topRight,
        target: Alignment.bottomRight,
        // On a phone the button's target runs to within a few pixels of the
        // screen's edge, so the menu is pulled in to the phone's 16 px
        // gutter rather than lining up with it.
        offset: Offset(
          MediaQuery.sizeOf(context).width < TABLET
              ? -(ArDriveSpacing.md - _targetInset)
              : 0,
          0,
        ),
        // The button is at the row's trailing edge and the menu is wider than
        // the room left of it on a phone, so without this it opens past the
        // screen's left edge and takes every item's icon with it.
        shiftToWithinBound: const AxisFlag(x: true),
      ),
      items: driveMenuItems(
        context,
        drive: drive,
        isOwner: isOwner,
        isSynced: isSynced,
        isSyncing: isSyncing,
        onMoreInfo: _moreInfo(context),
      ),
      // The name once. The tooltip carries its message to a screen reader as
      // well, so with a label of its own inside it the button was announced
      // as "Show menu Show menu".
      child: Semantics(
        button: true,
        label: appLocalizationsOf(context).showMenu,
        excludeSemantics: true,
        child: ArDriveClickArea(
          tooltip: appLocalizationsOf(context).showMenu,
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
