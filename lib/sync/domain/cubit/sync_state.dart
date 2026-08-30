part of 'sync_cubit.dart';

@immutable
abstract class SyncState extends Equatable {
  @override
  List<Object> get props => [];
}

class SyncIdle extends SyncState {}

/// Loading drive metadata only (not full sync).
/// Used when syncAllDrivesOnLogin is disabled.
/// This is a lightweight UI-only state that doesn't block waitCurrentSync().
class SyncLoadingDrives extends SyncState {}

class SyncInProgress extends SyncState {
  /// Who asked for this sync. The shell only blocks the app for a sync the
  /// user asked for; see [SyncOverlay].
  final SyncTrigger trigger;

  SyncInProgress({this.trigger = SyncTrigger.userInitiated});

  @override
  List<Object> get props => [trigger];
}

/// A sync that could not be done at all, as against one that got through some
/// drives and not others - see [SyncCompleteWithErrors].
///
/// `syncMetadataOnly` is the only place this is terminal: everywhere else
/// `onError` emits it and `SyncIdle` in the same turn, so it flashes past.
/// Terminal is what makes it worth reporting - it means the drive list itself
/// could not be read, and stays true until something refreshes it.
class SyncFailure extends SyncState {
  final Object? error;
  final StackTrace? stackTrace;

  /// When it failed, on the same terms as [SyncCompleteWithErrors.completedAt]
  /// and deliberately out of [props] for the same reason: the top bar's
  /// announcement is entitled to a few seconds from the moment of the failure,
  /// not a fresh few seconds every time something rebuilds the bar.
  final DateTime failedAt;

  SyncFailure({this.error, this.stackTrace, DateTime? failedAt})
      : failedAt = failedAt ?? DateTime.now();
}

class SyncEmpty extends SyncState {}

class SyncWalletMismatch extends SyncState {}

class SyncCancelled extends SyncState {
  final int drivesCompleted;
  final int totalDrives;
  final DateTime cancelledAt;

  /// Who asked for the sync that was cancelled. Cancelling is only reachable
  /// from the modal, which only a user-initiated sync gets, so this is
  /// [SyncTrigger.userInitiated] in practice - but it follows the sync it came
  /// from rather than assuming.
  final SyncTrigger trigger;

  SyncCancelled({
    required this.drivesCompleted,
    required this.totalDrives,
    required this.cancelledAt,
    this.trigger = SyncTrigger.userInitiated,
  });

  @override
  List<Object> get props =>
      [drivesCompleted, totalDrives, cancelledAt, trigger];
}

class SyncCompleteWithErrors extends SyncState {
  final int failedDrives;
  final int totalDrives;
  final List<String> failedDriveIds;
  final Map<String, String> errorMessages;

  /// Entities dropped from this sync because their metadata could not be read.
  /// See [SyncCubit.lastSyncSkippedEntityTxIdsByDrive].
  final int skippedEntityCount;
  final Map<String, List<String>> skippedEntityTxIdsByDrive;

  /// Who asked for the sync that failed, like every other terminal state.
  ///
  /// It was the only one without a trigger, so [SyncOverlay.blocksTheApp]
  /// returned true for it unconditionally: a login sync that paints nothing
  /// while it runs would still drop a scrim and a modal over whatever the user
  /// was doing the moment one drive out of five came back empty. A sync nobody
  /// asked for reports its failure where it ran - the top bar - and a sync the
  /// user asked for keeps the modal it was already holding.
  final SyncTrigger trigger;

  /// When the sync that failed finished.
  ///
  /// Deliberately NOT in [props]: it exists so a surface can tell how long ago
  /// this happened, not to make two otherwise-identical failures distinct. A
  /// background failure is announced at the top bar for a few seconds, and
  /// this state stays current until the next sync runs - so without it, every
  /// rebuild of the top bar replayed the announcement from the beginning.
  final DateTime completedAt;

  SyncCompleteWithErrors({
    required this.failedDrives,
    required this.totalDrives,
    required this.failedDriveIds,
    required this.errorMessages,
    this.skippedEntityCount = 0,
    this.skippedEntityTxIdsByDrive = const {},
    this.trigger = SyncTrigger.userInitiated,
    DateTime? completedAt,
  }) : completedAt = completedAt ?? DateTime.now();

  @override
  List<Object> get props => [
        failedDrives,
        totalDrives,
        failedDriveIds,
        errorMessages,
        skippedEntityCount,
        skippedEntityTxIdsByDrive,
        trigger,
      ];
}

/// A sync that finished, and what it found.
///
/// It extends [SyncIdle] deliberately. `DriveDetailCubit` refreshes the open
/// drive on `syncState is SyncIdle`, and `SharingFileListener` hands a shared
/// file over on the same test; a sibling state would leave both waiting,
/// silently, for a sync that had already finished. Subclassing keeps every
/// existing `is SyncIdle` true while letting the two surfaces that report the
/// result match `is SyncComplete`.
///
/// Only a sync that ran and got to the end emits this. A sync that was turned
/// away before it started - a hidden tab, an upload in progress - still emits a
/// plain [SyncIdle], because it has nothing to report.
class SyncComplete extends SyncIdle {
  SyncComplete({
    required this.entitiesSynced,
    required this.sequence,
    required this.completedAt,
    this.skippedEntityCount = 0,
    this.isSingleDriveSync = false,
    this.driveName,
    this.trigger = SyncTrigger.userInitiated,
  });

  /// File and folder revisions this sync wrote, straight off [SyncProgress].
  ///
  /// Deliberately not accompanied by a count of drives. `drivesSynced` counts
  /// drives *walked*, failures included, so "12 new items across 3 drives"
  /// sent a user whose twelve files all landed in one drive looking through
  /// three - and "1 new item across 3 drives" is not a thing that can happen.
  /// The two numbers do not belong in one sentence, and the number of drives
  /// a sync looked at is not a result worth reporting on its own.
  final int entitiesSynced;

  /// Entities dropped because their metadata could not be read - files the
  /// user will not see, so the summary says so rather than claiming a clean
  /// result. See [SyncCubit.lastSyncSkippedEntityTxIdsByDrive].
  final int skippedEntityCount;

  /// Whether this was a sync of one named drive rather than all of them, and
  /// which drive it was, so the summary can name it.
  final bool isSingleDriveSync;
  final String? driveName;

  /// Who asked for the sync that produced this. It decides which surface
  /// reports it: the top bar for a sync nobody asked for, the modal it is
  /// already showing for one the user did.
  final SyncTrigger trigger;

  /// When it finished, so a surface can refuse to announce a result that has
  /// been sitting in the cubit's state for an hour - see `syncSummaryIsFresh`.
  /// Never the discriminator: see [sequence].
  final DateTime completedAt;

  /// Which result this is, counted up by the cubit that emitted it.
  ///
  /// Bloc drops a state equal to the one it is already in, and two zero-change
  /// syncs carry identical counts - so a result needs something that tells it
  /// apart from the one before, or the second one goes unreported. A timestamp
  /// cannot be that thing: `DateTime.now()` is only millisecond-grained here,
  /// and two syncs with no I/O between them land inside the same millisecond
  /// often enough to drop a result in the app and to fail a test at random.
  final int sequence;

  @override
  List<Object> get props => [
        entitiesSynced,
        skippedEntityCount,
        isSingleDriveSync,
        // Equatable rejects a nullable member here. Collapsing null and '' is
        // safe for identity only - the summary itself distinguishes them, and
        // treats an empty name as no name.
        driveName ?? '',
        trigger,
        sequence,
      ];
}
