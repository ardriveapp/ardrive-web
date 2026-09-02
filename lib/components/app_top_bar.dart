import 'dart:async';

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/search/search_modal.dart';
import 'package:ardrive/search/search_text_field.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/presentation/sync_elapsed_time.dart';
import 'package:ardrive/sync/presentation/sync_summary.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/sync/presentation/sync_history_panel.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_custom_event_properties.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The bar's own row, which is all of it. Nothing about a sync is laid out
/// here: the indicator in the row is the whole of what a sync costs the
/// chrome, and everything it has to say is behind a tap on it.
const double _topBarRowHeight = 110;

class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();

    return SizedBox(
      height: _topBarRowHeight,
      width: double.maxFinite,
      child: Padding(
        padding: const EdgeInsets.only(right: 17.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SearchTextField(
                  controller: controller,
                  onFieldSubmitted: (query) {
                    showSearchModalDesktop(
                      context: context,
                      driveDetailCubit: context.read<DriveDetailCubit>(),
                      controller: controller,
                      drivesCubit: context.read<DrivesCubit>(),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 24),
            const Spacer(),
            const GlobalHideToggleButton(),
            const SizedBox(width: 8),
            const SyncButton(),
            const SizedBox(width: 8),
            const SizedBox(width: 24),
            const ProfileCard(),
          ],
        ),
      ),
    );
  }
}

class GlobalHideToggleButton extends StatelessWidget {
  const GlobalHideToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GlobalHideBloc, GlobalHideState>(
      builder: (context, hideState) {
        if (!hideState.userHasHiddenDrive) {
          return const SizedBox.shrink();
        }

        final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

        final tooltip = hideState is ShowingHiddenItems
            ? 'Hide hidden items'
            : 'Show hidden items';

        final icon = hideState is ShowingHiddenItems
            ? ArDriveIcons.eyeOpen(
                color: colorTokens.textMid,
              )
            : ArDriveIcons.eyeClosed(
                color: colorTokens.textMid,
              );

        return ArDriveIconButton(
          tooltip: tooltip,
          icon: icon,
          onPressed: () {
            context.read<GlobalHideBloc>().add(
                  hideState is ShowingHiddenItems
                      ? HideItems(
                          userHasHiddenItems: hideState.userHasHiddenDrive)
                      : ShowItems(
                          userHasHiddenItems: hideState.userHasHiddenDrive,
                        ),
                );
          },
        );
      },
    );
  }
}

/// The size [ArDriveIcon] renders at by default, and so the size of the slot
/// every state of [SyncButton] has to fit into for the top bar to hold still
/// when a sync starts or stops.
const double _syncIndicatorSize = 24;

/// Exposed so a test can compare it with [syncGlyphSizeWhileSyncing] - the
/// pair is what the eye compares when a sync starts.
const double syncIndicatorSize = _syncIndicatorSize;

/// How far the ring is drawn inside its box, so its ink matches a glyph's.
const double _syncRingInset = 2;

/// The refresh glyph inside the ring.
///
/// Smaller than the indicator because the ring is drawn around it, but not by
/// half: the same glyph is [_syncIndicatorSize] when nothing is running, and a
/// control that halves when it becomes busy reads as a different control.
const double _syncGlyphSize = 14;

/// See [syncIndicatorSize].
const double syncGlyphSizeWhileSyncing = _syncGlyphSize;

/// See [syncIndicatorSize].
const double syncRingInset = _syncRingInset;

/// How wide an announcement is allowed to get before it wraps. On a phone this
/// is most of the screen.
const double _syncAnnouncementMaxWidth = 260;

/// What the sync indicator has to say, in the words the sync summary uses for
/// the same thing.
///
/// Read twice: by the tooltip, for a pointer that has somewhere to hover, and
/// by [_SyncStatusHeader] at the top of the menu, for the tap that is the only
/// way to ask this question on a phone.
class _SyncStatus {
  const _SyncStatus({
    required this.title,
    this.detail,
    this.showElapsed = false,
    this.isError = false,
    this.detailMaxLines = 1,
  });

  /// What is being synced - which drive, by name, when the sync is for one -
  /// or, for a sync that failed, was cancelled, or was started under a wallet
  /// that has since changed, what happened.
  final String title;

  /// What is happening inside that: the count of metadata reads while they are
  /// in flight, the phase the sync names for itself otherwise, the percentage
  /// when it names none, or what a sync that did not finish left behind.
  final String? detail;

  /// Whether the sync this describes is running, and so has a start time worth
  /// counting from. `syncStartTime` holds the *last* sync's start, so a header
  /// counting from it when nothing is running would report minutes.
  final bool showElapsed;

  /// Whether this is a problem rather than progress, so the indicator reads as
  /// one.
  final bool isError;

  /// How much room [detail] gets. A running sync's phase is one short line; a
  /// failure counts drives, which wraps on a phone.
  final int detailMaxLines;

  /// The same two lines, for a pointer that has somewhere to hover.
  String get asTooltip => detail == null ? title : '$title\n$detail';
}

/// The row height [ArDriveDropdown] assumes for every item: it sizes its
/// overlay as `items.length * height`, so a header taller than one row has to
/// be paid for with an explicit `maxHeight`.
const double _dropdownRowHeight = 48;

/// What the status header asks for at the default text scale, and the reason
/// [_SyncButtonMenu] hands the dropdown a `maxHeight` whenever it shows one.
///
/// A minimum, not a cap: a larger text scale grows the header and the menu
/// scrolls, rather than the header being cut off.
const double _syncStatusHeaderMinHeight = 108;

/// How wide the status header lets the menu grow. The dropdown wraps its items
/// in an [IntrinsicWidth], so this is what sets the open menu's width while a
/// sync runs - and it is inside the narrowest phone this app is built for.
const double _syncStatusHeaderWidth = 260;

/// What the top bar has to say about a sync that just ended, and for how long.
class SyncAnnouncement {
  const SyncAnnouncement({
    required this.identity,
    required this.showFor,
    this.lead,
    this.trailing,
    this.isError = false,
    this.onDone,
  });

  /// Which announcement this is. A new identity restarts the few seconds it
  /// gets; the same one arriving again because something rebuilt does not, so
  /// a result cannot be stretched by a resize - and two syncs that read
  /// identically are still two results, because their identities differ.
  final Object identity;

  /// How long it stays, counted from when the sync ended rather than from when
  /// this was built - see [syncSummaryRemaining].
  final Duration showFor;

  /// The line that may be shortened when there is not room for everything.
  final String? lead;

  /// The line that may not: what a sync could not read is the whole reason for
  /// saying anything, so it never gets ellipsized in favour of a drive name.
  final String? trailing;

  /// Whether this is a failure. It is drawn as one - a report nobody asked for
  /// must not be mistaken for a clean result.
  final bool isError;

  /// Run once, when the announcement's time is up.
  ///
  /// This exists for exactly one state. [SyncCancelled] is a resting state the
  /// cubit stays in until something else syncs, and two things wait on
  /// [SyncIdle] to do their work - the explorer's refresh and the shared-file
  /// handover. Its only way back to idle used to be the OK button on a modal
  /// that no longer exists, so without this a cancelled sync would leave both
  /// of them waiting for an emission that was never coming. It is the same
  /// `clearCancelledState()` that button called, moved to the end of the
  /// announcement that replaced it.
  final VoidCallback? onDone;
}

/// The top bar's sync control, and the whole of what a sync costs the chrome:
/// the ring that turns while one runs, the menu behind it, and the place every
/// way a sync can end reports itself.
///
/// Three levels, and only the first is ever on screen unasked. The ring is
/// level nought - a sync is running, and that is all a working app needs to
/// say. A tap opens level one: [_SyncStatusHeader], which names the drive, the
/// phase or the count of metadata reads in flight, and how long this has been
/// going on. The menu's last row opens level two, the sync history in the
/// Troubleshooting modal, which is the record of what every recent sync did.
///
/// What *happened* is announced here too: a result, a partial failure, a
/// failure to read the drive list at all, a sync that was cancelled, and a
/// wallet that changed under a sync - each for a few seconds beside the
/// indicator, and each left on the indicator itself afterwards so a report
/// nobody was watching for is still reachable.
class SyncButton extends StatelessWidget {
  const SyncButton({super.key});

  @override
  Widget build(BuildContext context) {
    // Outermost and unconditional, so the shape below it never changes - see
    // the note on the StreamBuilder. It is here for one string: the name of
    // the drive a single-drive sync is walking.
    return BlocBuilder<DrivesCubit, DrivesState>(
      builder: (context, drivesState) => BlocBuilder<SyncCubit, SyncState>(
        builder: (context, syncState) {
          final syncCubit = context.read<SyncCubit>();

          // One shape for every state, and that is the point. This slot used to
          // hold three structurally different subtrees - the menu on its own
          // when idle, a StreamBuilder above it while a sync ran, a flash above
          // that just after one finished - so every transition changed the
          // widget type at this position and took [ArDriveDropdown]'s element,
          // and its open/closed flag, down with it. An open menu vanished the
          // instant a sync started or ended, and a thumb already moving towards
          // Resync landed on the page behind.
          //
          // The stream is subscribed to in every state rather than only while
          // a sync runs. It is a broadcast controller the cubit already owns,
          // so listening costs nothing and asks nobody for anything.
          return StreamBuilder<SyncProgress>(
            stream: syncCubit.syncProgressController.stream,
            // The controller replays nothing, so a button mounted mid-sync
            // would show an empty ring until the next event without this.
            initialData: syncCubit.syncProgress,
            builder: (context, snapshot) => _build(
              context,
              syncState,
              snapshot.data,
              _syncingDriveName(syncCubit, drivesState),
            ),
          );
        },
      ),
    );
  }

  /// The name of the drive a single-drive sync is walking, or null.
  ///
  /// Two halves, and neither knows the other's: [SyncCubit.syncingDriveId]
  /// knows *which* drive from the first frame of the sync, and [DrivesCubit]
  /// is the only thing that knows what it is called. [SyncProgress] carries a
  /// name as well, but only once the repository has read the drive out of the
  /// database - and it was never rendered anywhere, so a single-drive sync
  /// reported itself as "Syncing Drive" and named nothing at all.
  ///
  /// Null for a sync of every drive, which has no one drive to name, and null
  /// for a drive the list has not loaded yet - in which case the title falls
  /// back to the unnamed wording rather than inventing one.
  String? _syncingDriveName(SyncCubit syncCubit, DrivesState drivesState) {
    final driveId = syncCubit.syncingDriveId;

    if (driveId == null || drivesState is! DrivesLoadSuccess) {
      return null;
    }

    for (final drive in [
      ...drivesState.userDrives,
      ...drivesState.sharedDrives,
    ]) {
      if (drive.id == driveId) {
        return drive.name;
      }
    }

    return null;
  }

  Widget _build(
    BuildContext context,
    SyncState syncState,
    SyncProgress? syncProgress,
    String? syncingDriveName,
  ) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // Every partial failure, whoever asked for the sync. It used to be only
    // the ones nobody asked for, because a user-initiated sync was holding a
    // modal that said the same thing with the same retry - and that modal is
    // gone, so this is the only surface left. Filtering here now would leave a
    // sync the user pressed a button for reporting its failures nowhere at
    // all.
    final errors = syncState is SyncCompleteWithErrors ? syncState : null;

    // A sync that could not be done at all, as against one that got through
    // some drives and not others. `syncMetadataOnly` is the only place this is
    // terminal, and it is the whole of a default login - so without a branch
    // for it the button fell through to the idle refresh icon and the app
    // looked fully synced while showing nothing, permanently, with only a
    // snackbar that had already gone. `autoSync` is false in all three
    // flavours, so nothing was going to retry it either.
    final failure = syncState is SyncFailure ? syncState : null;

    // A sync that was stopped part way. Only the debug failure panel can ask
    // for this now - the modal that carried the Cancel button is gone - but
    // the state is still reachable, and a state with no surface is the thing
    // this pass exists to remove.
    final cancelled = syncState is SyncCancelled ? syncState : null;

    // The ArConnect wallet changed under the sync, so the user was signed out.
    // This was emitted and rendered nowhere: the user was bounced to login
    // with no explanation from the layer that noticed.
    final walletMismatch = syncState is SyncWalletMismatch;

    final isSyncing = syncState is SyncInProgress;

    final _SyncStatus? status;
    final Widget indicator;

    if (syncState is SyncLoadingDrives) {
      // Loading drive metadata reports no progress at all, so the ring has
      // nothing to fill and just turns.
      status = _SyncStatus(
        title: syncLoadingDrivesLabel(appLocalizationsOf(context), syncState),
      );
      indicator = const _SyncProgressRing();
    } else if (isSyncing) {
      status = _syncStatus(context, syncProgress, syncingDriveName);
      // A phase that cannot measure itself hands the ring no value, so it
      // sweeps as well as turns - the same honesty the modal's bar gets. The
      // rotation is its own repeating animation either way, so the ring never
      // freezes into a static arc.
      indicator = _SyncProgressRing(
        progress: syncProgress != null && syncProgress.isIndeterminate
            ? null
            : syncProgress?.progress,
      );
    } else if (errors != null) {
      status = _SyncStatus(
        title: appLocalizationsOf(context).syncCompleteWithErrors,
        detail: appLocalizationsOf(context).syncDrivesFailed(
          errors.failedDrives,
          errors.totalDrives,
        ),
        isError: true,
        detailMaxLines: 2,
      );
      indicator = ArDriveIcons.triangle(color: colorTokens.strokeRed);
    } else if (failure != null) {
      // The same surface, the same tokens and the same red triangle a partial
      // failure gets: two ways of failing, reported one way.
      status = _SyncStatus(
        title: appLocalizationsOf(context).syncFailed,
        detail: appLocalizationsOf(context).syncFailedDetail,
        isError: true,
        detailMaxLines: 2,
      );
      indicator = ArDriveIcons.triangle(color: colorTokens.strokeRed);
    } else if (walletMismatch) {
      status = _SyncStatus(
        title: appLocalizationsOf(context).syncWalletChanged,
        detail: appLocalizationsOf(context).syncWalletChangedDetail,
        isError: true,
        detailMaxLines: 2,
      );
      indicator = ArDriveIcons.triangle(color: colorTokens.strokeRed);
    } else if (cancelled != null) {
      // Not drawn as a failure: nothing went wrong, the sync was stopped. The
      // indicator stays the idle glyph - nothing is running and nothing is
      // broken - and the words say what was left unfinished.
      status = _SyncStatus(
        title: appLocalizationsOf(context).syncCancelled,
        detail: appLocalizationsOf(context).syncCancelledDrives(
          cancelled.drivesCompleted,
          cancelled.totalDrives,
        ),
        detailMaxLines: 2,
      );
      indicator = ArDriveIcons.refresh(color: colorTokens.textMid);
    } else {
      status = null;
      indicator = ArDriveIcons.refresh(color: colorTokens.textMid);
    }

    return SyncSummaryFlash(
      announcement: _announcement(
        context,
        syncState,
        errors,
        failure,
        cancelled,
        walletMismatch,
      ),
      child: _SyncButtonMenu(
        status: status,
        isSyncing: isSyncing,
        failedDriveIds: errors?.failedDriveIds,
        refreshFailed: failure != null,
        child: indicator,
      ),
    );
  }

  /// What the button has to announce right now, or null when it has nothing.
  SyncAnnouncement? _announcement(
    BuildContext context,
    SyncState syncState,
    SyncCompleteWithErrors? errors,
    SyncFailure? failure,
    SyncCancelled? cancelled,
    bool walletMismatch,
  ) {
    if (errors != null) {
      // Gated the same way a result is: SyncCompleteWithErrors stays the
      // cubit's state until the next sync, so without this the red pill
      // replayed in full every time the top bar was rebuilt - on every drive
      // click, for the rest of the session.
      final remaining = syncSummaryRemainingSince(errors.completedAt);
      if (remaining == Duration.zero) {
        return null;
      }

      return SyncAnnouncement(
        // The state itself. Two failures that read identically are equal, so
        // bloc would never deliver the second one anyway - and a failure that
        // has been cleared and happened again is a different object.
        identity: errors,
        showFor: remaining,
        lead: appLocalizationsOf(context).syncCompleteWithErrors,
        trailing: appLocalizationsOf(context).syncDrivesFailed(
          errors.failedDrives,
          errors.totalDrives,
        ),
        isError: true,
      );
    }

    if (failure != null) {
      // Gated off the moment of the failure, exactly like a partial one: the
      // state stays current until something refreshes the drive list, so an
      // announcement counted from build time would replay on every rebuild for
      // the rest of the session. The indicator and the menu are what carry it
      // after the few seconds are up.
      final remaining = syncSummaryRemainingSince(failure.failedAt);
      if (remaining == Duration.zero) {
        return null;
      }

      return SyncAnnouncement(
        // The timestamp, not the state: SyncFailure has no props, so every
        // failure is equal to every other one and using the state itself would
        // silence a second failure after an intervening SyncIdle.
        identity: failure.failedAt,
        showFor: remaining,
        lead: appLocalizationsOf(context).syncFailed,
        trailing: appLocalizationsOf(context).syncFailedDetail,
        isError: true,
      );
    }

    if (walletMismatch) {
      return SyncAnnouncement(
        // The state itself. It carries no timestamp and every instance is
        // equal to every other, so bloc delivers it at most once anyway.
        identity: syncState,
        showFor: syncSummaryDuration,
        lead: appLocalizationsOf(context).syncWalletChanged,
        trailing: appLocalizationsOf(context).syncWalletChangedDetail,
        isError: true,
      );
    }

    if (cancelled != null) {
      return SyncAnnouncement(
        // The state, which carries the moment it was cancelled in its props,
        // so a second cancellation is a second announcement.
        identity: cancelled,
        // Not counted from when it was cancelled, unlike the others: this
        // announcement is what returns the cubit to idle, so it has to run to
        // the end even if it was mounted late.
        showFor: syncSummaryDuration,
        lead: appLocalizationsOf(context).syncCancelled,
        trailing: appLocalizationsOf(context).syncCancelledDrives(
          cancelled.drivesCompleted,
          cancelled.totalDrives,
        ),
        onDone: () => context.read<SyncCubit>().clearCancelledState(),
      );
    }

    if (syncState is SyncComplete &&
        syncState.trigger != SyncTrigger.userInitiated &&
        // A result that has already had its few seconds is not announced again
        // because the bar was rebuilt - see [syncSummaryIsFresh].
        syncSummaryIsFresh(syncState)) {
      final summary = syncCompleteSummaryParts(
        appLocalizationsOf(context),
        syncState,
      );

      return SyncAnnouncement(
        // Which result this is, not what it says: two zero-change syncs read
        // identically, and the second one still has to show.
        identity: syncState.sequence,
        showFor: syncSummaryRemaining(syncState),
        lead: summary.arrived,
        trailing: summary.unreadable,
      );
    }

    return null;
  }

  /// What a running sync has to say: which sync it is, what it is doing inside
  /// that, and - through [_SyncStatus.showElapsed] - how long it has been at
  /// it.
  _SyncStatus _syncStatus(
    BuildContext context,
    SyncProgress? syncProgress,
    String? syncingDriveName,
  ) {
    return _SyncStatus(
      title: _syncTitle(context, syncProgress, syncingDriveName),
      detail: syncProgress == null ? null : _syncDetail(context, syncProgress),
      showElapsed: true,
    );
  }

  /// Which sync this is, by name where there is one.
  String _syncTitle(
    BuildContext context,
    SyncProgress? syncProgress,
    String? syncingDriveName,
  ) {
    // Either half is enough to know this is a sync of one drive: the cubit's
    // drive id is set before the first progress event, and the progress flag
    // survives after the id is released.
    final isSingleDrive =
        syncingDriveName != null || (syncProgress?.isSingleDriveSync ?? false);

    if (!isSingleDrive) {
      return appLocalizationsOf(context).syncingAllDrives;
    }

    final driveName = syncingDriveName ?? syncProgress?.driveName;

    if (driveName == null || driveName.isEmpty) {
      // The drive list has not loaded, so there is no name to give. Saying
      // which drive is better than not saying; inventing one is worse than
      // both.
      return appLocalizationsOf(context).syncingSingleDrive;
    }

    return appLocalizationsOf(context).syncingDriveWithName(driveName);
  }

  /// What is happening inside that sync.
  ///
  /// The metadata fetch first, and ahead of the phase's own name, because it
  /// is the only figure that moves during the phase it belongs to: every
  /// revision's metadata is one request, a few at a time, and "Reading the
  /// drive history..." sat unchanged over all of them. Then the phase, because
  /// the sync names it. Then the percentage, which stands in only when the
  /// sync has no phase to name and a number worth showing - an unmeasurable
  /// phase always has a message, and a percentage that cannot move is what a
  /// hang looks like.
  String? _syncDetail(BuildContext context, SyncProgress syncProgress) {
    // Zero is a phase with nothing of this kind to report, not a fetch of
    // nothing. Only the count is shown: the total was "what has been asked
    // for so far", which the count catches at every batch boundary, so the
    // only figure that ever sat on screen long enough to read was "N of N".
    if (syncProgress.metadataFetchesCompleted > 0) {
      return appLocalizationsOf(context)
          .syncReadingMetadata(syncProgress.metadataFetchesCompleted);
    }

    final statusMessage = syncProgress.statusMessage;

    if (statusMessage != null) {
      return statusMessage;
    }

    if (syncProgress.isIndeterminate) {
      return null;
    }

    return appLocalizationsOf(context).syncProgressPercentage(
      (syncProgress.progress * 100).round().toString(),
    );
  }
}

/// What a finished background sync found - or could not - beside the indicator
/// that was turning for it, for [syncSummaryDuration] and no longer.
///
/// It hangs off the button in an overlay rather than in the top bar's own row:
/// a result that arrives while the user is reading something else must not
/// push the bar's contents sideways, and it has to be able to leave again
/// without moving them back.
///
/// It is mounted in every state, with nothing to say in most of them, so that
/// the button's subtree does not change shape when a sync ends - see
/// [SyncButton].
class SyncSummaryFlash extends StatefulWidget {
  const SyncSummaryFlash({
    super.key,
    required this.announcement,
    required this.child,
  });

  /// What there is to say, or null when there is nothing.
  final SyncAnnouncement? announcement;

  /// The sync button the announcement is anchored to.
  final Widget child;

  @override
  State<SyncSummaryFlash> createState() => _SyncSummaryFlashState();
}

class _SyncSummaryFlashState extends State<SyncSummaryFlash> {
  Timer? _dismiss;

  /// The identity of the announcement that has already had its turn. Kept
  /// after it is hidden: without it, the next rebuild would find the same
  /// announcement still on the cubit's state and start it over.
  Object? _announced;

  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _announce();
  }

  @override
  void didUpdateWidget(covariant SyncSummaryFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    // No setState: a build follows this immediately.
    _announce();
  }

  void _announce() {
    final announcement = widget.announcement;

    if (announcement == null) {
      _dismiss?.cancel();
      _dismiss = null;
      _announced = null;
      _visible = false;
      return;
    }

    if (announcement.identity == _announced) {
      return;
    }

    _announced = announcement.identity;
    _visible = true;
    _dismiss?.cancel();
    _dismiss = Timer(announcement.showFor, () {
      if (mounted) {
        setState(() => _visible = false);
      }
      // After the setState, and unconditionally: an announcement whose whole
      // job is to release a resting state has to release it even if this
      // widget has been rebuilt out from under the timer.
      announcement.onDone?.call();
    });
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final announcement = widget.announcement;

    return ArDriveOverlay(
      visible: _visible && announcement != null,
      // No barrier: a report is not a question, so it never takes the next
      // click - the resync menu underneath still opens on the first one.
      closeOnBarrierTap: false,
      anchor: const Aligned(
        follower: Alignment.topRight,
        target: Alignment.bottomRight,
        offset: Offset(0, 8),
        // The button sits at the top bar's trailing edge, so on a phone the
        // summary is wider than the room left of it.
        shiftToWithinBound: AxisFlag(x: true),
      ),
      content: announcement == null
          ? const SizedBox.shrink()
          : _SyncSummaryPill(announcement: announcement),
      child: widget.child,
    );
  }
}

/// The announcement itself: a quiet couple of lines in the surface colours, so
/// a result that needs nothing from the user does not read like a warning - and
/// in the red tokens when it is one, so a failure is never mistaken for a
/// clean result.
///
/// The pill is capped at [_syncAnnouncementMaxWidth], which on a phone is most of
/// the screen, so [SyncAnnouncement.lead] is allowed two lines and then an
/// ellipsis. [SyncAnnouncement.trailing] is not: it goes on its own line
/// underneath, full length. On one line it was joined last, so a long drive
/// name pushed it past the cap and the ellipsis ate exactly the clause that
/// says this sync has holes in it.
class _SyncSummaryPill extends StatelessWidget {
  const _SyncSummaryPill({required this.announcement});

  final SyncAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final lead = announcement.lead;
    final trailing = announcement.trailing;
    final textColor =
        announcement.isError ? colorTokens.textRed : colorTokens.textHigh;

    return IgnorePointer(
      // The margin is what keeps a gutter on the narrowest phone: the anchor's
      // shiftToWithinBound pulls the follower to x=0, so without it the pill
      // sits flush against the screen edge while its right side keeps its
      // inset, and reads as misaligned rather than as a floating card.
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        constraints: const BoxConstraints(maxWidth: _syncAnnouncementMaxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorTokens.containerL1,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: announcement.isError
                ? colorTokens.strokeRed
                : colorTokens.strokeLow,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lead != null)
              Text(
                lead,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: typography.paragraphSmall(color: textColor),
              ),
            if (trailing != null)
              Text(
                trailing,
                style: typography.paragraphSmall(color: textColor),
              ),
          ],
        ),
      ),
    );
  }
}

/// The resync menu every state of [SyncButton] hangs off, so that a running
/// sync never costs the user the actions - and, above the actions, the answer
/// to "what is it doing".
///
/// This is level one. The header is not decoration and not a duplicate of
/// something on screen: nothing else in the app says which sync is running,
/// which drive it is for, what phase it is in or how long it has been going.
/// It is a tap rather than a hover because a phone has neither a pointer nor a
/// tooltip, and both breakpoints mount this same menu.
class _SyncButtonMenu extends StatelessWidget {
  const _SyncButtonMenu({
    this.status,
    this.isSyncing = false,
    this.failedDriveIds,
    this.refreshFailed = false,
    required this.child,
  });

  /// The running sync, or how the last one ended - the header's lines, the
  /// tooltip's, and how the menu knows whether it has anything to say at all.
  final _SyncStatus? status;

  /// Whether a sync is running. The cubit refuses a second one outright, so an
  /// item that looks normal, closes the menu, records a Plausible event and
  /// drops the request would be a lie. These say what they are instead.
  final bool isSyncing;

  /// The drives a background sync failed on, when it did: the retry has to
  /// outlive the few seconds the announcement gets.
  final List<String>? failedDriveIds;

  /// Whether the drive-list refresh itself failed, so the menu carries a way
  /// to run it again. There are no failed drive ids to retry in this case -
  /// the sync never got as far as a drive.
  final bool refreshFailed;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final failedDriveIds = this.failedDriveIds;
    final iconColor = ArDriveTheme.of(context).themeData.colors.themeFgDefault;

    final items = [
      ArDriveDropdownItem(
        // Nothing at all rather than a call that returns immediately: an event
        // must not be recorded for a sync that never starts.
        onClick: isSyncing
            ? null
            : () {
                context.read<SyncCubit>().startSync(deepSync: false);
                context.read<ProfileNameBloc>().add(RefreshProfileName());
                PlausibleEventTracker.trackResync(type: ResyncType.resync);
              },
        content: ArDriveDropdownItemTile(
          name: appLocalizationsOf(context).resync,
          isDisabled: isSyncing,
          icon: ArDriveIcons.refresh(color: iconColor),
        ),
      ),
      ArDriveDropdownItem(
        onClick: isSyncing
            ? null
            : () {
                context.read<SyncCubit>().startSync(deepSync: true);
                context.read<ProfileNameBloc>().add(RefreshProfileName());
                PlausibleEventTracker.trackResync(type: ResyncType.deepResync);
              },
        content: ArDriveDropdownItemTile(
          name: appLocalizationsOf(context).deepResync,
          isDisabled: isSyncing,
          icon: ArDriveIcons.cloudSync(color: iconColor),
        ),
      ),
      if (failedDriveIds != null && failedDriveIds.isNotEmpty)
        ArDriveDropdownItem(
          onClick: isSyncing
              ? null
              : () {
                  final syncCubit = context.read<SyncCubit>();
                  syncCubit.clearErrorState();
                  syncCubit.retryFailedDrives(failedDriveIds);
                },
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).retryFailedDrives,
            isDisabled: isSyncing,
            icon: ArDriveIcons.cloudSync(color: iconColor),
          ),
        ),
      if (refreshFailed)
        ArDriveDropdownItem(
          // `syncMetadataOnly` and nothing more: it is the request that
          // failed, and it leaves the user's syncAllDrivesOnLogin preference
          // alone. Resync, one row up, is still there for a full one.
          onClick: isSyncing
              ? null
              : () => context.read<SyncCubit>().syncMetadataOnly(),
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).tryAgain,
            isDisabled: isSyncing,
            icon: ArDriveIcons.refresh(color: iconColor),
          ),
        ),
      // One row, not a list. This menu sizes itself as `items.length * 48` and
      // closes on any tap inside it, so it is the wrong container for a
      // scrolling record - the row is a door to level two, which is the sync
      // history in the Troubleshooting modal, beside the diagnostic logs a
      // user with a problem is already there to send. Live during a sync as
      // well: reading what the last few syncs did is exactly what somebody
      // watching a slow one wants.
      ArDriveDropdownItem(
        onClick: () => showSyncHistoryModal(context),
        content: ArDriveDropdownItemTile(
          name: appLocalizationsOf(context).syncHistory,
          icon: ArDriveIcons.info(color: iconColor),
        ),
      ),
    ];

    // The dropdown would otherwise size itself as `items.length * 48` and cut
    // the header off. Scaled with the user's text, because the header grows
    // with it - past the viewport the overlay clamps this and the menu
    // scrolls, which is the outcome we want rather than a header sliced in
    // half.
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return HoverWidget(
      tooltip: status?.asTooltip ?? appLocalizationsOf(context).resyncTooltip,
      child: ArDriveDropdown(
        anchor: const Aligned(
          follower: Alignment.topRight,
          target: Alignment.bottomRight,
          // The menu hangs off the top bar's trailing edge, so on a narrow
          // phone it is wider than the room left of the button. Let the portal
          // pull it back rather than run the text off the left edge.
          shiftToWithinBound: AxisFlag(x: true),
        ),
        maxHeight: status == null
            ? null
            : (_syncStatusHeaderMinHeight + items.length * _dropdownRowHeight) *
                textScale,
        // A header rather than an item: it is there to be read, so it must not
        // light up like an action or close the menu when a thumb lands on it.
        header: status == null ? null : _SyncStatusHeader(status: status),
        items: items,
        child: SizedBox(
          width: _syncIndicatorSize,
          height: _syncIndicatorSize,
          child: child,
        ),
      ),
    );
  }
}

/// The key the status header hangs off, so a test can find it whatever it
/// currently says.
const Key syncStatusHeaderKey = Key('syncStatusHeader');

/// Level one: which sync is running, which drive it is for, what it is doing
/// and how long it has been doing it - or, when one has just gone wrong, what
/// happened.
///
/// It sits above the resync actions in the menu the sync indicator opens, and
/// it is the only place in the app any of this is said. The ring alone says a
/// sync is running; this says the rest, on a tap, without a pointer, on both
/// breakpoints.
class _SyncStatusHeader extends StatelessWidget {
  const _SyncStatusHeader({required this.status});

  final _SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final detail = status.detail;

    return Container(
      key: syncStatusHeaderKey,
      width: _syncStatusHeaderWidth,
      constraints: const BoxConstraints(minHeight: _syncStatusHeaderMinHeight),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorTokens.strokeLow),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status.isError) ...[
                ArDriveIcons.triangle(
                  size: 16,
                  color: colorTokens.strokeRed,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  status.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: status.isError
                        ? colorTokens.textRed
                        : colorTokens.textHigh,
                  ),
                ),
              ),
            ],
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                detail,
                maxLines: status.detailMaxLines,
                overflow: TextOverflow.ellipsis,
                style: typography.paragraphSmall(
                  color: colorTokens.textMid,
                ),
              ),
            ),
          if (status.showElapsed)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: SyncElapsedTime(),
            ),
        ],
      ),
    );
  }
}

/// The key the ring's continuous rotation hangs off, so a test can prove the
/// indicator is still moving.
const Key syncIndicatorMotionKey = Key('syncIndicatorMotion');

/// A turning ring with the refresh glyph inside it, filling the slot the idle
/// icon leaves behind.
///
/// [progress] fills the ring once the sync reports any - but the ring turns
/// either way. Sync progress plateaus for long stretches, and an arc that has
/// not moved in a minute reads as a hang, so the arc keeps rotating whatever
/// its length is doing.
class _SyncProgressRing extends StatefulWidget {
  const _SyncProgressRing({this.progress});

  final double? progress;

  @override
  State<_SyncProgressRing> createState() => _SyncProgressRingState();
}

class _SyncProgressRingState extends State<_SyncProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;

  @override
  void initState() {
    super.initState();
    // Built here rather than lazily on first use, so dispose() never has to
    // create a ticker on a widget that is already coming down.
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final progress = widget.progress;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Inset so the ring's ink lands where a glyph's ink lands. A 24px
        // ring is drawn edge to edge, while a 24px icon carries its own
        // padding and only draws about 20 - so at the same nominal size the
        // ring reads visibly larger than the way home beside it. The box stays
        // 24 either way, so nothing moves in the row.
        Padding(
          padding: const EdgeInsets.all(_syncRingInset),
          child: RotationTransition(
            key: syncIndicatorMotionKey,
            turns: _rotation,
            child: CircularProgressIndicator(
              value: progress != null && progress > 0 ? progress : null,
              strokeWidth: 2,
              backgroundColor: colorTokens.strokeHigh,
              valueColor: AlwaysStoppedAnimation<Color>(
                colorTokens.buttonPrimaryDefault,
              ),
            ),
          ),
        ),
        // The same token the idle icon uses, so the glyph does not change
        // colour the instant a sync starts - and near enough the same size,
        // so it does not visibly shrink either. At half the indicator it went
        // from 24 to 12 the moment a sync began, which read as the button
        // changing rather than the ring appearing around it. This is as large
        // as it goes inside a 2px ring with clearance either side.
        ArDriveIcons.refresh(
          size: _syncGlyphSize,
          color: colorTokens.textMid,
        ),
      ],
    );
  }
}
