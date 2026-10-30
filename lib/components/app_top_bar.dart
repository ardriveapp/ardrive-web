import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/publication/presentation/publication_chrome.dart';
import 'package:ardrive/publication/presentation/publication_loader_page.dart';
import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/search/search_box.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/presentation/sync_elapsed_time.dart';
import 'package:ardrive/sync/presentation/sync_summary.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The bar's own row, which is all of it. Nothing about a sync is laid out
/// here: the indicator in the row is the whole of what a sync costs the
/// chrome, and everything it has to say is behind a tap on it.
const double _topBarRowHeight = 110;

class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _topBarRowHeight,
      width: double.maxFinite,
      child: Padding(
        padding: const EdgeInsets.only(right: ArDriveSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // A publication has no sidebar, so its icon leads the bar.
            if (PublicationMode.isOn) ...[
              PublicationIcon(config: publicationConfigOf(context), size: 40),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: const SearchBox(),
              ),
            ),
            const SizedBox(width: 24),
            const Spacer(),
            // A publication has no hidden items to show, nothing to sync and
            // no account (docs/PUBLICATIONS.md, "The publication frame").
            if (PublicationMode.isOn)
              const PublicationTopBarActions()
            else ...[
              const GlobalHideToggleButton(),
              const SizedBox(width: 8),
              const SyncButton(),
              const SizedBox(width: 8),
              const SizedBox(width: 24),
              const ProfileCard(),
            ],
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

/// The button's outer size, which is the indicator plus the hover padding
/// wrapped around it. The placeholder that holds the slot while there is
/// nothing to report has to match this and not the indicator, or the bar still
/// moves - just by less.
const double _syncButtonOuterSize = _syncIndicatorSize + 2 * ArDriveSpacing.xxs;

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
    this.tone = _SyncTone.plain,
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

  /// What kind of report this is, so the header says it in that status's
  /// words: a result, a warning, a failure, or plain progress.
  final _SyncTone tone;

  /// How much room [detail] gets. A running sync's phase is one short line; a
  /// failure counts drives, which wraps on a phone.
  final int detailMaxLines;

  /// The same two lines, for a pointer that has somewhere to hover.
  String get asTooltip => detail == null ? title : '$title\n$detail';
}

/// How a sync report is drawn. A result that needs nothing reads as success, a
/// result with holes in it as a warning, and a failure as an error, in
/// ardrive_ui's status colours (README, Status colours).
enum _SyncTone { plain, success, warning, error }

extension on _SyncTone {
  ArDriveStatusType? get statusType => switch (this) {
        _SyncTone.plain => null,
        _SyncTone.success => ArDriveStatusType.success,
        _SyncTone.warning => ArDriveStatusType.warning,
        _SyncTone.error => ArDriveStatusType.error,
      };
}

/// The row height [ArDriveDropdown] assumes for every item: it sizes its
/// overlay as `items.length * height`, so a header taller than one row has to
/// be paid for with an explicit `maxHeight`.
const double _dropdownRowHeight = 48;

/// The most the status header is allowed at the default text scale: a two-line
/// title, a two-line detail and the elapsed time, inside its padding.
///
/// A cap, not a size. The menu is told to fit its content, so a one-line
/// header takes one line's height; this only bounds how far the menu may grow
/// before it scrolls, scaled with the reader's text.
const double _syncStatusHeaderMaxHeight = 132;

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
    this.isWarning = false,
    this.warnOnTrailing = false,
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

  /// Whether this is a result with something wrong in it, such as items that
  /// could not be read. Drawn as a warning, not as a clean result.
  final bool isWarning;

  /// Whether the warning is about [trailing] rather than [lead]: a result's
  /// lead says what changed, which is not the part that went wrong.
  final bool warnOnTrailing;

  /// What a screen reader is told when this first shows.
  String get spoken => [
        if (lead != null) lead!,
        if (trailing != null) trailing!,
      ].join('. ');

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
              drivesState,
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
  /// Null for a drive the list has not loaded yet - in which case the title
  /// falls back to the unnamed wording rather than inventing one.
  static String? _driveName(DrivesState drivesState, String? driveId) {
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
    DrivesState drivesState,
  ) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final l10n = appLocalizationsOf(context);
    final syncCubit = context.read<SyncCubit>();

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

    // A sync that was stopped part way: first as the state the cubit stops in,
    // then, once that has been announced, as the rest it moves on to. The
    // drives it did not finish are marked on the drives list too.
    final cancelled = syncState is SyncCancelled ? syncState : null;
    final stopped = syncState is SyncStopped ? syncState : null;

    // The ArConnect wallet changed under the sync, so the user was signed out.
    // This was emitted and rendered nowhere: the user was bounced to login
    // with no explanation from the layer that noticed.
    final walletMismatch = syncState is SyncWalletMismatch;

    // A sync that finished. Its result stays on the indicator until the next
    // sync or until it is dismissed: the few seconds the pill gets are too
    // short to read (WCAG 2.2.1), so the pill is only the announcement and the
    // indicator is where the result can still be read.
    final complete = syncState is SyncComplete ? syncState : null;

    final isSyncing = syncState is SyncInProgress;

    final _SyncStatus? status;
    final Widget indicator;

    if (syncState is SyncLoadingDrives) {
      // Loading drive metadata reports no progress at all, so the ring has
      // nothing to fill and just turns.
      status = _SyncStatus(
        title: syncLoadingDrivesLabel(l10n, syncState),
      );
      indicator = const _SyncProgressRing();
    } else if (isSyncing) {
      status = _syncStatus(context, syncCubit, syncProgress, drivesState);
      // A phase that cannot measure itself hands the ring no value, so it
      // sweeps and turns. A phase that can is drawn still, so how full the
      // ring is can be read.
      indicator = _SyncProgressRing(
        progress: syncProgress != null && syncProgress.isIndeterminate
            ? null
            : syncProgress?.progress,
      );
    } else if (errors != null) {
      // Every drive failing is a failure, not an incomplete sync: nothing was
      // synced.
      final allFailed =
          errors.totalDrives > 0 && errors.failedDrives >= errors.totalDrives;
      status = _SyncStatus(
        title: allFailed
            ? l10n.syncAllDrivesFailed(errors.totalDrives)
            : l10n.syncCompleteWithErrors,
        detail: allFailed
            ? null
            : l10n.syncDrivesFailed(errors.failedDrives, errors.totalDrives),
        tone: _SyncTone.error,
        detailMaxLines: 2,
      );
      indicator = ArDriveIcons.triangle(color: colorTokens.strokeRed);
    } else if (failure != null) {
      // The same surface, the same tokens and the same red triangle a partial
      // failure gets: two ways of failing, reported one way.
      final (title, detail) = _failureWords(context, failure, drivesState);
      status = _SyncStatus(
        title: title,
        detail: detail,
        tone: _SyncTone.error,
        detailMaxLines: 2,
      );
      indicator = ArDriveIcons.triangle(color: colorTokens.strokeRed);
    } else if (walletMismatch) {
      status = _SyncStatus(
        title: l10n.syncWalletChanged,
        detail: l10n.syncWalletChangedDetail,
        tone: _SyncTone.error,
        detailMaxLines: 2,
      );
      indicator = ArDriveIcons.triangle(color: colorTokens.strokeRed);
    } else if (cancelled != null || stopped != null) {
      // Not drawn as a failure: nothing went wrong, the sync was stopped. It
      // is a warning, because the drives it did not finish are half read.
      status = _SyncStatus(
        title: l10n.syncCancelled,
        detail: l10n.syncCancelledDrives(
          cancelled?.drivesCompleted ?? stopped!.drivesCompleted,
          cancelled?.totalDrives ?? stopped!.totalDrives,
        ),
        tone: _SyncTone.warning,
        detailMaxLines: 2,
      );
      indicator = ArDriveIcons.triangle(color: colorTokens.statusWarningFg);
    } else if (complete != null) {
      final summary = syncCompleteSummaryParts(l10n, complete);
      // Items that could not be read are a hole in the result, so a result
      // with any is a warning rather than a success.
      final hasHoles = summary.unreadable != null;
      status = _SyncStatus(
        title: summary.arrived ?? summary.unreadable!,
        detail: summary.arrived == null ? null : summary.unreadable,
        tone: hasHoles ? _SyncTone.warning : _SyncTone.success,
        detailMaxLines: 2,
      );
      indicator = hasHoles
          ? ArDriveIcons.triangle(color: colorTokens.statusWarningFg)
          : ArDriveIcons.checkCirle(color: colorTokens.statusSuccessFg);
    } else {
      status = null;
      indicator = ArDriveIcons.refresh(color: colorTokens.textMid);
    }

    // Present only when there is something to report. A control that is idle
    // almost always is ambient noise in the one corner that should be quiet,
    // and every other level of this report already follows the rule: say
    // nothing when there is nothing to say. The actions moved to the drives
    // list, where the drives they act on are.
    if (status == null) {
      // The slot is held, not collapsed. Removing the widget entirely moved
      // everything beside it the instant a sync began - and the control whose
      // job is to report calmly must not shove the account card sideways to do
      // it. Nothing is drawn; the space stays.
      return const SizedBox(
        width: _syncButtonOuterSize,
        height: _syncButtonOuterSize,
      );
    }

    final announcement = _announcement(
      context,
      syncState,
      errors,
      failure,
      cancelled,
      walletMismatch,
      status,
    );

    return SyncSummaryFlash(
      announcement: announcement,
      child: _SyncButtonMenu(
        status: status,
        isSyncing: isSyncing,
        failedDriveIds: errors?.failedDriveIds,
        failure: failure,
        // Every report of how a sync ended can be put away, except a drive
        // list that could not be read: the drives page reads that state to
        // avoid saying the account has no drives.
        canDismiss: !isSyncing &&
            syncState is! SyncLoadingDrives &&
            !walletMismatch &&
            !(failure != null && failure.kind == SyncFailureKind.driveList),
        child: indicator,
      ),
    );
  }

  /// What a failure says, by what failed.
  ///
  /// A drive list that could not be refreshed while drives read earlier are on
  /// screen is not "Drives could not be loaded": they did load. A sync that
  /// read the list and then stopped on a drive is not a load failure at all.
  (String, String?) _failureWords(
    BuildContext context,
    SyncFailure failure,
    DrivesState drivesState,
  ) {
    final l10n = appLocalizationsOf(context);

    if (failure.kind == SyncFailureKind.sync) {
      final driveName =
          failure.driveName ?? _driveName(drivesState, failure.singleDriveId);
      return (
        l10n.syncStoppedWithError,
        driveName == null || driveName.isEmpty
            ? null
            : l10n.syncStoppedWithErrorDrive(driveName),
      );
    }

    final drivesShown =
        drivesState is DrivesLoadSuccess && !drivesState.hasNoDrives;

    return drivesShown
        ? (l10n.syncDriveListCheckFailed, l10n.syncDriveListCheckFailedDetail)
        : (l10n.syncFailed, l10n.syncFailedDetail);
  }

  /// What the button has to announce right now, or null when it has nothing.
  ///
  /// Every announcement says what [status] says, so the pill and the menu
  /// header can never disagree.
  SyncAnnouncement? _announcement(
    BuildContext context,
    SyncState syncState,
    SyncCompleteWithErrors? errors,
    SyncFailure? failure,
    SyncCancelled? cancelled,
    bool walletMismatch,
    _SyncStatus status,
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
        lead: status.title,
        trailing: status.detail,
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
        lead: status.title,
        trailing: status.detail,
        isError: true,
      );
    }

    if (walletMismatch) {
      return SyncAnnouncement(
        // The state itself. It carries no timestamp and every instance is
        // equal to every other, so bloc delivers it at most once anyway.
        identity: syncState,
        showFor: syncSummaryDuration,
        lead: status.title,
        trailing: status.detail,
        isError: true,
      );
    }

    if (cancelled != null) {
      return SyncAnnouncement(
        // The state, which carries the moment it was cancelled in its props,
        // so a second cancellation is a second announcement.
        identity: cancelled,
        // Not counted from when it was cancelled, unlike the others: this
        // announcement is what moves the cubit on to rest, so it has to run to
        // the end even if it was mounted late.
        showFor: syncSummaryDuration,
        lead: status.title,
        trailing: status.detail,
        isWarning: true,
        onDone: () => context.read<SyncCubit>().clearCancelledState(),
      );
    }

    // Every outcome reports here, whoever asked for it. A sync the user pressed
    // used to get a card in the middle of the screen instead - full width on a
    // phone, 226px tall, over the page they were reading - while the same
    // result from a background sync got this pill, anchored under the control
    // that was turning. Two designs for one sentence, and the trigger decided
    // which. Failures never split that way: they have always come here.
    if (syncState is SyncComplete &&
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
        isWarning: summary.unreadable != null,
        warnOnTrailing: true,
      );
    }

    return null;
  }

  /// What a running sync has to say: which sync it is, what it is doing inside
  /// that, and - through [_SyncStatus.showElapsed] - how long it has been at
  /// it.
  _SyncStatus _syncStatus(
    BuildContext context,
    SyncCubit syncCubit,
    SyncProgress? syncProgress,
    DrivesState drivesState,
  ) {
    return _SyncStatus(
      title: _syncTitle(context, syncCubit, syncProgress, drivesState),
      detail: syncProgress == null ? null : _syncDetail(context, syncProgress),
      showElapsed: true,
    );
  }

  /// Which sync this is, by name where there is one.
  String _syncTitle(
    BuildContext context,
    SyncCubit syncCubit,
    SyncProgress? syncProgress,
    DrivesState drivesState,
  ) {
    final syncingDriveName = _driveName(drivesState, syncCubit.syncingDriveId);

    // Either half is enough to know this is a sync of one drive: the cubit's
    // drive id is set before the first progress event, and the progress flag
    // survives after the id is released.
    final isSingleDrive =
        syncingDriveName != null || (syncProgress?.isSingleDriveSync ?? false);

    if (!isSingleDrive) {
      // A run over some of the drives - the ticked ones, the ones that failed,
      // the ones that changed - says how many, or which when it is one. Only
      // a run over every drive is "all drives".
      final runDriveIds = syncCubit.syncingDriveIds;
      if (runDriveIds != null && runDriveIds.isNotEmpty) {
        final onlyName = runDriveIds.length == 1
            ? _driveName(drivesState, runDriveIds.first)
            : null;
        return onlyName != null && onlyName.isNotEmpty
            ? appLocalizationsOf(context).syncingDriveWithName(onlyName)
            : appLocalizationsOf(context).syncingSomeDrives(runDriveIds.length);
      }
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
    _speak(announcement.spoken);
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

  /// Tells a screen reader what happened, once per announcement. The pill is
  /// drawn in an overlay a screen reader is not watching, so without this a
  /// sync that finished or failed was never heard of.
  void _speak(String text) {
    if (text.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SemanticsService.announce(text, Directionality.of(context));
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

/// The announcement itself: a quiet couple of lines on the raised surface, so
/// a result that needs nothing from the user does not read like a warning - in
/// the warning status when something in it could not be read, and in the red
/// tokens when it failed, so neither is mistaken for a clean result.
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
    // Which line carries the status icon, if either does.
    final ArDriveStatusType? leadType = announcement.isError
        ? ArDriveStatusType.error
        : announcement.isWarning && !announcement.warnOnTrailing
            ? ArDriveStatusType.warning
            : null;
    final ArDriveStatusType? trailingType = announcement.isError && lead == null
        ? ArDriveStatusType.error
        : announcement.isWarning && announcement.warnOnTrailing
            ? ArDriveStatusType.warning
            : null;
    return IgnorePointer(
      // The margin is what keeps a gutter on the narrowest phone: the anchor's
      // shiftToWithinBound pulls the follower to x=0, so without it the pill
      // sits flush against the screen edge while its right side keeps its
      // inset, and reads as misaligned rather than as a floating card.
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: ArDriveSpacing.xs),
        constraints: const BoxConstraints(maxWidth: _syncAnnouncementMaxWidth),
        padding: const EdgeInsets.symmetric(
          horizontal: ArDriveSpacing.sm,
          vertical: ArDriveSpacing.xs,
        ),
        // A card floating over the page: the raised surface, radius md and a
        // shadow, as a menu is. It used to be the button radius on a low
        // surface with no shadow, a grey box laid flat on a white page.
        decoration: BoxDecoration(
          color: colorTokens.containerRaised,
          borderRadius: BorderRadius.circular(ArDriveRadius.md),
          boxShadow: [
            ArDriveTheme.of(context).themeData.shadows.boxShadow60(),
          ],
          border: Border.all(
            color: announcement.isError
                ? colorTokens.strokeRed
                : announcement.isWarning
                    ? colorTokens.statusWarningStroke
                    : colorTokens.strokeLow,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A failure is said as ardrive_ui's error status text: red, with
            // the error icon once, beside the first line. A warning is said
            // the same way on the line it is about: the lead for a stopped
            // sync, the trailing line for a result with items it could not
            // read.
            if (lead != null)
              leadType != null
                  ? ArDriveStatusText(
                      text: lead,
                      type: leadType,
                      maxLines: 2,
                    )
                  : Text(
                      lead,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: typography.paragraphSmall(
                        color: colorTokens.textHigh,
                      ),
                    ),
            if (trailing != null)
              trailingType != null
                  ? ArDriveStatusText(
                      text: trailing,
                      type: trailingType,
                    )
                  : Padding(
                      // Under the lead's words, past its icon.
                      padding: EdgeInsetsDirectional.only(
                        // Where [ArDriveStatusText]'s words start: its icon
                        // (the font size plus 2) and the gap after it.
                        start: leadType != null && lead != null
                            ? (typography.paragraphSmall().fontSize ?? 14) +
                                2 +
                                ArDriveSpacing.xxs
                            : 0,
                      ),
                      child: Text(
                        trailing,
                        style: typography.paragraphSmall(
                          color: announcement.isError
                              ? colorTokens.statusErrorFg
                              : colorTokens.textHigh,
                        ),
                      ),
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
    required this.status,
    this.isSyncing = false,
    this.failedDriveIds,
    this.failure,
    this.canDismiss = false,
    required this.child,
  });

  /// The running sync, or how the last one ended - the header's lines and the
  /// tooltip's.
  final _SyncStatus status;

  /// Whether a sync is running. The cubit refuses a second one outright, so an
  /// item that looks normal, closes the menu, records a Plausible event and
  /// drops the request would be a lie. These say what they are instead.
  final bool isSyncing;

  /// The drives a background sync failed on, when it did: the retry has to
  /// outlive the few seconds the announcement gets.
  final List<String>? failedDriveIds;

  /// The sync that could not be done at all, when that is what happened, so
  /// the menu can run it again. It says what it was doing: the drive-list
  /// refresh, one drive, some drives or all of them.
  final SyncFailure? failure;

  /// Whether the report can be put away. See [SyncCubit.dismissSyncResult].
  final bool canDismiss;

  final Widget child;

  /// Runs again exactly what failed: the drive-list refresh, the sync that
  /// stopped, or the drives the last sync could not read.
  ///
  /// The same calls the drives list makes for the same failures. A drive
  /// retry may ask the wallet again for the failed drives whose prompt was
  /// cancelled, and for no other drive; the drive-list refresh never asks.
  void _tryAgain(BuildContext context) {
    final syncCubit = context.read<SyncCubit>();
    final failure = this.failure;

    if (failure != null) {
      // Through the drives list when it is the page saying the list could not
      // be loaded: its own Try again keeps it on "still looking" for the
      // length of the retry, where a refresh it did not start would flash
      // Getting Started over an empty table. Nullable, because only that
      // route provides it.
      final drivesList = context.read<DrivesListCubit?>();
      if (failure.kind == SyncFailureKind.driveList &&
          drivesList != null &&
          drivesList.state is DrivesListUnavailable) {
        drivesList.retryLoadingDrives();
      } else {
        syncCubit.retryFailure();
      }
      return;
    }

    final failedDriveIds = this.failedDriveIds;
    if (failedDriveIds != null && failedDriveIds.isNotEmpty) {
      syncCubit.clearErrorState();
      syncCubit.retryFailedDrives(failedDriveIds);
    }
  }

  /// Whether there is something that failed and can be run again.
  bool get _canTryAgain =>
      failure != null || (failedDriveIds?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final iconColor = ArDriveTheme.of(context).themeData.colorTokens.textHigh;

    // Status, then what answers it. The sync actions live on the drives list -
    // Sync all, Full resync and the record are all drive-wide, and that is the
    // page about drives. This indicator only appears when there is something
    // to report, so it carries only what answers the report: a way out of a
    // sync that is running, a way past one that failed, and a way to put the
    // report away. No navigation: the sidebar is always the way to the drives
    // list.
    final items = [
      // The way out of a sync that is going to take longer than the reader is
      // willing to wait.
      //
      // The engine has always been able to stop one - both entry points carry
      // a cancellation token and both report SyncCancelled - but the only
      // control that asked for it was the blocking modal, and that went when
      // sync stopped taking the app away. So a drive with a million
      // transactions could be started and not stopped, which is the one case
      // the feature exists for. This is where a running sync is already
      // reported, so it is where the way to stop it belongs.
      if (isSyncing)
        ArDriveDropdownItem(
          onClick: () => context.read<SyncCubit>().cancelSync(),
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).syncStopRunning,
            icon: ArDriveIcons.x(color: iconColor),
          ),
        ),
      // A failure is reported here and outlives its announcement, so the way
      // to run it again is here too, rather than only on a page the reader
      // may not be on.
      if (!isSyncing && _canTryAgain)
        ArDriveDropdownItem(
          onClick: () => _tryAgain(context),
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).tryAgain,
            icon: ArDriveIcons.refresh(color: iconColor),
          ),
        ),
      // A result stays here until the next sync, so the reader can take it
      // away sooner.
      if (canDismiss)
        ArDriveDropdownItem(
          onClick: () => context.read<SyncCubit>().dismissSyncResult(),
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).syncDismiss,
            icon: ArDriveIcons.x(color: iconColor),
          ),
        ),
    ];

    // The header is as tall as its text, so the menu is told to fit what is
    // in it and is given only a cap. Scaled with the user's text, because the
    // header grows with it - past the cap the menu scrolls, rather than the
    // header being sliced in half.
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return HoverWidget(
      tooltip: status.asTooltip,
      child: ArDriveDropdown(
        anchor: const Aligned(
          follower: Alignment.topRight,
          target: Alignment.bottomRight,
          // The menu hangs off the top bar's trailing edge, so on a narrow
          // phone it is wider than the room left of the button. Let the portal
          // pull it back rather than run the text off the left edge.
          shiftToWithinBound: AxisFlag(x: true),
        ),
        fitContent: true,
        maxHeight:
            (_syncStatusHeaderMaxHeight + items.length * _dropdownRowHeight) *
                textScale,
        // A header rather than an item: it is there to be read, so it must not
        // light up like an action or close the menu when a thumb lands on it.
        header: _SyncStatusHeader(status: status),
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
    final statusType = status.tone.statusType;

    return Container(
      key: syncStatusHeaderKey,
      width: _syncStatusHeaderWidth,
      // As tall as its lines, with no minimum: a one-line header used to sit
      // in a fixed 108px with most of it blank. The menu rows' own side
      // padding, so the header's words line up with the items under it.
      padding: const EdgeInsets.symmetric(
        horizontal: ArDriveSpacing.md,
        vertical: ArDriveSpacing.sm,
      ),
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
          // A result, a warning or a failure is ardrive_ui's status text in
          // that status; a running sync a plain title.
          if (statusType != null)
            ArDriveStatusText(
              text: status.title,
              type: statusType,
              maxLines: 2,
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.semiBold,
              ),
            )
          else
            Text(
              status.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.semiBold,
                color: colorTokens.textHigh,
              ),
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
/// [progress] fills the ring once the sync reports any, and then the ring holds
/// still so how full it is can be read: a ring that turns while it fills
/// cannot be read at all. Only a ring with nothing to measure turns, which is
/// what says the sync is working while it has no figure to give.
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
    );
    _turnWhenUnmeasured();
  }

  @override
  void didUpdateWidget(covariant _SyncProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _turnWhenUnmeasured();
  }

  /// Whether the ring has a figure to show. See [_SyncProgressRing].
  bool get _measured {
    final progress = widget.progress;
    return progress != null && progress > 0;
  }

  /// Turns the ring while it has nothing to measure, and stops it, upright,
  /// once it has.
  void _turnWhenUnmeasured() {
    if (_measured) {
      _rotation.reset();
    } else if (!_rotation.isAnimating) {
      _rotation.repeat();
    }
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
    final measured = _measured;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Inset so the ring's ink lands where a glyph's ink lands. A 24px
        // ring is drawn edge to edge, while a 24px icon carries its own
        // padding and only draws about 20 - so at the same nominal size the
        // ring reads visibly larger than the way home beside it. The box stays
        // 24 either way, so nothing moves in the row.
        //
        // The ring turns on every frame of a sync: its own layer, so a frame
        // repaints the ring and not the top bar around it. On the HTML
        // renderer, which phones get, a repaint rebuilds the DOM of
        // everything it covers.
        RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.all(_syncRingInset),
            child: RotationTransition(
              key: syncIndicatorMotionKey,
              turns: _rotation,
              // A progress ring around the refresh glyph, not a loading
              // spinner, so it is drawn here rather than with ArDriveSpinner.
              child: CircularProgressIndicator(
                value: measured ? progress : null,
                strokeWidth: 2,
                backgroundColor: colorTokens.strokeHigh,
                valueColor: AlwaysStoppedAnimation<Color>(
                  colorTokens.buttonPrimaryDefault,
                ),
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
