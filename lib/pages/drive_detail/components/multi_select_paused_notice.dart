import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Says that selecting several items is off while a sync is running, for as
/// long as it is, and nothing at all the rest of the time.
///
/// The lock itself predates this widget: multi-select is held shut while a sync
/// runs because the actions behind it would act on rows the sync is rewriting
/// underneath them, and that is worth keeping. What changed is that a
/// background sync no longer scrims the app, so the user is browsing for the
/// whole of it - minutes, on a large wallet - and ctrl/cmd-click and ctrl-A
/// were hard no-ops with nothing disabled and nothing said. That reads as the
/// app being broken rather than as the app being busy.
///
/// One quiet line above the list, and no dialog: nothing is wrong and nothing
/// is being asked, the app is briefly not offering something it usually does.
class MultiSelectPausedNotice extends StatelessWidget {
  const MultiSelectPausedNotice({super.key, required this.driveId});

  /// The drive on screen, so the notice appears only when the sync running is
  /// one that actually holds this drive's selection shut.
  final String driveId;

  /// Whether a running sync is holding multi-select shut.
  ///
  /// The single source of truth for both halves of this: the flag the data
  /// table is locked with, and whether this notice appears. Deriving them
  /// separately is how the two drift apart and the lock goes quiet again.
  /// Only a sync that could be writing *this* drive holds it shut.
  ///
  /// This used to be `state is SyncInProgress`, so syncing one drive disabled
  /// selection in every other one - including drives that sync was never going
  /// to touch. The rule the explorer already uses to decide whether a drive
  /// can be opened at all is the right rule here too: the reason to hold
  /// selection is that the rows under it are being rewritten, which is only
  /// true of the drive being written.
  ///
  /// An all-drives sync still holds everything, because it really is writing
  /// everything.
  ///
  /// Deliberately *not* [SyncCubit.syncTouchesDrive], though the drive half is
  /// the same test. That one also counts `SyncLoadingDrives`, because a drive
  /// list being rewritten is a reason to wait before opening a drive - but it
  /// rewrites no rows inside an open folder, so it is not a reason to hold a
  /// selection in one.
  static bool locksMultiSelect(
    SyncState state, {
    required String? syncingDriveId,
    required String driveId,
  }) =>
      state is SyncInProgress &&
      (syncingDriveId == null || syncingDriveId == driveId);

  @override
  Widget build(BuildContext context) {
    if (!locksMultiSelect(
      context.watch<SyncCubit>().state,
      syncingDriveId: context.watch<SyncCubit>().syncingDriveId,
      driveId: driveId,
    )) {
      return const SizedBox.shrink();
    }

    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ArDriveIcons.info(size: 16, color: colorTokens.textLow),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              appLocalizationsOf(context).multiSelectPausedWhileSyncing,
              style: typography.paragraphSmall(color: colorTokens.textLow),
            ),
          ),
        ],
      ),
    );
  }
}
