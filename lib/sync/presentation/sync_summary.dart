import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// How long a finished sync's summary stays on screen before it takes itself
/// away. Long enough to read a line, short enough that nobody has to dismiss
/// it: neither surface asks for a click.
const Duration syncSummaryDuration = Duration(seconds: 4);

/// The separator between the two halves of a summary that has both - what
/// arrived, and what could not be read.
const String _summaryJoin = ' · ';

/// Whether a finished sync is still worth announcing.
///
/// [SyncComplete] stays the cubit's state until the next sync runs, and both
/// surfaces start their countdown when they are first built rather than when
/// the sync finished. `app_shell` builds its stack separately in the desktop
/// and mobile branches of `ScreenTypeLayout`, so crossing the breakpoint an
/// hour after login rebuilds one from scratch - and would pop a fresh "Sync
/// Complete" for a sync that ended long ago. A result that has already had its
/// [syncSummaryDuration] does not get another one.
bool syncSummaryIsFresh(SyncComplete state, {DateTime? now}) =>
    syncSummaryRemaining(state, now: now) > Duration.zero;

/// How much of [syncSummaryDuration] a result has left.
///
/// A surface that starts a fresh [syncSummaryDuration] timer when it is built
/// shows a result for longer than it is entitled to: one built a moment before
/// the freshness boundary would run almost twice the intended time. The timer
/// is counted from when the sync finished, not from when something happened to
/// draw it.
Duration syncSummaryRemaining(SyncComplete state, {DateTime? now}) =>
    syncSummaryRemainingSince(state.completedAt, now: now);

/// [syncSummaryRemaining] for anything that carries a finish time - a failure
/// announces itself on the same terms a result does.
Duration syncSummaryRemainingSince(DateTime completedAt, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(completedAt);
  final remaining = syncSummaryDuration - elapsed;
  return remaining.isNegative ? Duration.zero : remaining;
}

/// What a finished sync found, in the two parts it can be broken into.
///
/// They are kept apart because they shorten differently. Joined into one line
/// the unreadable clause comes last, so on a narrow screen a long drive name
/// is what survives and "3 items could not be read" is what gets ellipsized -
/// exactly backwards, since the whole point of that clause is that a sync with
/// holes in it must not read as a clean one. A surface with a width limit lays
/// the two out as separate lines and lets only [arrived] shorten.
class SyncSummary {
  const SyncSummary({this.arrived, this.unreadable});

  /// What the sync brought in, or that it brought in nothing. Absent only when
  /// nothing arrived and something could not be read, where "up to date" would
  /// be a claim this sync cannot make.
  final String? arrived;

  /// How many entities were left out because their metadata could not be read.
  /// Absent when there were none.
  final String? unreadable;

  /// Both parts, in order, for a surface that can lay them out itself.
  List<String> get lines =>
      [if (arrived != null) arrived!, if (unreadable != null) unreadable!];

  /// Both parts on one line, for a surface with room for it.
  String get oneLine => lines.join(_summaryJoin);
}

/// What a finished sync found.
///
/// Every case has to say something. A sync that changed nothing is the case
/// that matters most: told "up to date - nothing new", the user learns that the
/// next sync is one they can ignore, which is the whole point of reporting a
/// result at all.
///
/// No case counts drives. `drivesSynced` counts drives walked, failures
/// included, so "across 3 drives" was two facts joined by a word that does not
/// hold between them. And no case says "new": a rename, a move or a new
/// version writes a revision too, so the count is what changed, not what
/// arrived - see [SyncComplete.entitiesSynced].
SyncSummary syncCompleteSummaryParts(
    AppLocalizations l10n, SyncComplete state) {
  final synced = state.entitiesSynced;
  final skipped = state.skippedEntityCount;
  final driveName = state.driveName;
  // Non-empty, not just non-null: an empty name renders " is up to date"
  // with a leading space, where a null one correctly falls back.
  final namesADrive =
      state.isSingleDriveSync && driveName != null && driveName.isNotEmpty;

  if (synced == 0 && skipped == 0) {
    return SyncSummary(
      arrived: namesADrive
          ? l10n.syncSummaryNothingNewInDrive(driveName)
          : l10n.syncSummaryNothingNew,
    );
  }

  return SyncSummary(
    arrived: synced > 0
        ? (namesADrive
            ? l10n.syncSummaryEntitiesInDrive(synced, driveName)
            : l10n.syncSummaryEntities(synced))
        : null,
    unreadable: skipped > 0 ? l10n.syncSummarySkippedEntities(skipped) : null,
  );
}

/// The whole summary on one line, for a surface that has the room.
String syncCompleteSummary(AppLocalizations l10n, SyncComplete state) =>
    syncCompleteSummaryParts(l10n, state).oneLine;

/// What every surface calls the moment the drive list is being read.
///
/// One function because three surfaces say it - the top bar's menu, the
/// explorer's panel and the drives list itself - and they report one sync
/// between them, so they must never name it differently.
///
/// The count only appears once there is one. Before the listing comes back
/// both figures are zero, and "0 of 0" is worse than saying nothing.
String syncLoadingDrivesLabel(
  AppLocalizations localizations,
  SyncState? state,
) {
  if (state is SyncLoadingDrives && state.hasCount) {
    return localizations.loadingYourDrivesCount(
      state.drivesRead,
      state.drivesFound,
    );
  }

  return localizations.loadingYourDrives;
}
