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

class SyncFailure extends SyncState {
  final Object? error;
  final StackTrace? stackTrace;

  SyncFailure({this.error, this.stackTrace});
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

  SyncCompleteWithErrors({
    required this.failedDrives,
    required this.totalDrives,
    required this.failedDriveIds,
    required this.errorMessages,
    this.skippedEntityCount = 0,
    this.skippedEntityTxIdsByDrive = const {},
  });

  @override
  List<Object> get props => [
        failedDrives,
        totalDrives,
        failedDriveIds,
        errorMessages,
        skippedEntityCount,
        skippedEntityTxIdsByDrive,
      ];
}
