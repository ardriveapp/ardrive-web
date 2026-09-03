import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/presentation/sync_history_panel.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_custom_event_properties.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Every drive-wide sync action, on the page about drives.
///
/// These lived behind the top bar's indicator, which was present on every
/// screen whether or not anything was happening. The indicator now appears only
/// when there is something to report, so the controls needed a home that is
/// always there - and the drives list is it: these all act on every drive, and
/// this is the page that lists them.
class DrivesSyncMenu extends StatelessWidget {
  const DrivesSyncMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final iconColor = ArDriveTheme.of(context).themeData.colors.themeFgDefault;
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return BlocBuilder<SyncCubit, SyncState>(
      builder: (context, syncState) {
        final isSyncing =
            syncState is SyncInProgress || syncState is SyncLoadingDrives;
        final errors = syncState is SyncCompleteWithErrors ? syncState : null;
        final nothingWalked = _nothingHasEverBeenWalked(context);

        // How many drives are ticked, so both actions can say which set they
        // will run over. Watched rather than read: ticking a drive has to
        // relabel these the moment it happens.
        //
        // Nullable because selection belongs to the drives list and this menu
        // does not: it needs SyncCubit to do its job and should not acquire a
        // second hard dependency for a label. Without one it behaves exactly
        // as it did before selection existed.
        final drivesList = context.watch<DrivesListCubit?>();
        final selection = drivesList?.selectionCount ?? 0;

        return ArDriveDropdown(
          anchor: const Aligned(
            follower: Alignment.topRight,
            target: Alignment.bottomRight,
            offset: Offset(0, 4),
            shiftToWithinBound: AxisFlag(x: true),
          ),
          items: [
            ArDriveDropdownItem(
              // Nothing at all rather than a call that returns immediately: an
              // event must not be recorded for a sync that never starts.
              onClick: isSyncing
                  ? null
                  : () {
                      // Acts on the ticked drives when there are any. A
                      // control that quietly ignored a selection the reader
                      // had just made would be the worst of both.
                      if (drivesList != null) {
                        drivesList.syncSelectedDrives(deep: false);
                      } else {
                        context.read<SyncCubit>().startSync(deepSync: false);
                      }
                      context.read<ProfileNameBloc>().add(RefreshProfileName());
                      PlausibleEventTracker.trackResync(
                          type: ResyncType.resync);
                    },
              content: ArDriveDropdownItemTile(
                // "Resync" is wrong before anything has ever synced. The word
                // promises a repeat of something that has not happened.
                name: selection > 0
                    ? appLocalizationsOf(context)
                        .driveListSyncSelectedCount(selection)
                    // "Resync" is wrong before anything has ever synced.
                    : nothingWalked
                        ? appLocalizationsOf(context).syncAllDrives
                        : appLocalizationsOf(context).resync,
                icon: ArDriveIcons.refresh(color: iconColor),
                isDisabled: isSyncing,
              ),
            ),
            ArDriveDropdownItem(
              onClick: isSyncing
                  ? null
                  : () {
                      if (drivesList != null) {
                        drivesList.syncSelectedDrives(deep: true);
                      } else {
                        context.read<SyncCubit>().startSync(deepSync: true);
                      }
                      PlausibleEventTracker.trackResync(
                          type: ResyncType.deepResync);
                    },
              content: ArDriveDropdownItemTile(
                name: selection > 0
                    ? appLocalizationsOf(context)
                        .driveListDeepResyncSelectedCount(selection)
                    : appLocalizationsOf(context).deepResync,
                icon: ArDriveIcons.cloudSync(color: iconColor),
                isDisabled: isSyncing,
              ),
            ),
            if (errors != null && errors.failedDriveIds.isNotEmpty)
              ArDriveDropdownItem(
                onClick: isSyncing
                    ? null
                    : () {
                        final cubit = context.read<SyncCubit>();
                        cubit.clearErrorState();
                        cubit.retryFailedDrives(errors.failedDriveIds);
                      },
                content: ArDriveDropdownItemTile(
                  name: appLocalizationsOf(context).retryFailedDrives,
                  icon: ArDriveIcons.triangle(color: iconColor),
                  isDisabled: isSyncing,
                ),
              ),
            ArDriveDropdownItem(
              onClick: () => showSyncHistoryModal(context),
              content: ArDriveDropdownItemTile(
                name: appLocalizationsOf(context).syncHistory,
                icon: ArDriveIcons.info(color: iconColor),
              ),
            ),
          ],
          // Styled as a button, but not one: `ArDriveDropdown` opens on a tap
          // that reaches it, and a real button swallows that tap with its own
          // handler - so the menu never opened. Every other dropdown in the app
          // passes an inert child for the same reason.
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              border: Border.all(color: colorTokens.strokeHigh),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  nothingWalked
                      ? appLocalizationsOf(context).syncAllDrives
                      : appLocalizationsOf(context).sync,
                  style: ArDriveTypographyNew.of(context).paragraphNormal(
                    color:
                        isSyncing ? colorTokens.textLow : colorTokens.textHigh,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
                const SizedBox(width: 8),
                ArDriveIcons.chevronDown(size: 16, color: colorTokens.textMid),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Whether nothing in this wallet has ever been walked, which decides whether
  /// the first action is a sync or a re-sync.
  static bool _nothingHasEverBeenWalked(BuildContext context) {
    final drives = context.watch<DrivesCubit>().state;

    if (drives is! DrivesLoadSuccess) {
      return false;
    }

    return drives.userDrives.isNotEmpty &&
        drives.userDrives.every((d) => (d.lastBlockHeight ?? 0) == 0);
  }
}
