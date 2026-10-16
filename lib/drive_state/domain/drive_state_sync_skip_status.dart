import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';

/// The D3 precondition, expressed as a question the creation path can ask:
/// **did the last sync of this drive leave anything out?**
///
/// `docs/drive-state/DECISIONS.md` D3 makes production an explicit user action
/// precisely so this is checkable, and `docs/DRIVE_STATE_ARTIFACT.md` §5 says
/// why it must be checked:
///
/// > A sync that reported skipped entities must not produce an artifact. Sync
/// > advances `lastBlockHeight` regardless of skips
/// > (`SYNC_SKIPPED_ENTITY_PERSISTENCE.md`), so publishing from that state
/// > would make a gap permanent and immutable.
///
/// The third answer is the one that earns this type. "I do not know" is not
/// the same as "clean", and the difference is the whole safety rail: an
/// artifact is written to Arweave, which has no delete, so a gap published by
/// a producer that *assumed* it was clean is permanent. Every path that cannot
/// establish cleanliness answers [DriveStateSyncSkipState.unknown] and the
/// creation service refuses.

/// What is known about the entities the last sync of a drive left out.
enum DriveStateSyncSkipState {
  /// A sync covering this drive ran to completion and reported nothing
  /// skipped.
  clean,

  /// A sync covering this drive reported entities it could not read.
  skipped,

  /// Nothing here is provable. No sync has finished, one is running, the last
  /// one was cancelled before it could report, or it never covered this drive.
  unknown,
}

/// The answer, with the sentence a refusal shows the user.
class DriveStateSyncSkipStatus {
  final DriveStateSyncSkipState state;

  /// How many entities the last sync skipped for this drive. Zero unless
  /// [state] is [DriveStateSyncSkipState.skipped].
  final int skippedEntityCount;

  /// Why the answer is what it is. Empty when [isClean]; otherwise a sentence
  /// naming the condition, because "cannot publish" without a reason is the
  /// silent failure this whole line of work came from.
  final String reason;

  const DriveStateSyncSkipStatus._(
    this.state,
    this.skippedEntityCount,
    this.reason,
  );

  const DriveStateSyncSkipStatus.clean() : this._(_clean, 0, '');

  const DriveStateSyncSkipStatus.skipped({
    required int skippedEntityCount,
    required String reason,
  }) : this._(_skipped, skippedEntityCount, reason);

  const DriveStateSyncSkipStatus.unknown(String reason)
      : this._(_unknown, 0, reason);

  static const _clean = DriveStateSyncSkipState.clean;
  static const _skipped = DriveStateSyncSkipState.skipped;
  static const _unknown = DriveStateSyncSkipState.unknown;

  bool get isClean => state == DriveStateSyncSkipState.clean;

  @override
  String toString() => isClean
      ? 'DriveStateSyncSkipStatus(clean)'
      : 'DriveStateSyncSkipStatus(${state.name}, $skippedEntityCount, $reason)';
}

/// Where the creation service gets its answer from.
///
/// An interface rather than a direct [SyncCubit] read so the precondition can
/// be exercised without a sync stack, and so a later pass that persists skips
/// across sessions (`docs/SYNC_SKIPPED_ENTITY_PERSISTENCE.md`) can replace the
/// source without touching the service.
abstract class DriveStateSyncSkipSource {
  DriveStateSyncSkipStatus statusFor(String driveId);
}

/// The [SyncCubit]-backed source: the only place skip state is surfaced today.
class SyncCubitDriveStateSkipSource implements DriveStateSyncSkipSource {
  final SyncCubit _syncCubit;

  const SyncCubitDriveStateSkipSource(this._syncCubit);

  @override
  DriveStateSyncSkipStatus statusFor(String driveId) =>
      driveStateSyncSkipStatus(
        driveId: driveId,
        syncState: _syncCubit.state,
        lastSyncCompletedAt: _syncCubit.lastSyncCompletedAt,
        coveredDriveIds: _syncCubit.lastSyncCoveredDriveIds,
        skippedEntityTxIdsByDrive: _syncCubit.lastSyncSkippedEntityTxIdsByDrive,
      );
}

/// The decision itself, as a function of what [SyncCubit] holds, so that every
/// branch of it is reachable in a test without building a sync stack.
///
/// Reads as a list of the ways "no skips were reported" can fail to mean "no
/// skips happened":
///
///  * a sync is still running, so its report does not exist yet;
///  * no sync has finished in this session, and the empty map that
///    [SyncCubit] starts with is indistinguishable from a clean one;
///  * the last sync was cancelled, and a cancelled sync never captures what it
///    skipped — it returns before the capture;
///  * the last sync was scoped to other drives, so its report says nothing
///    about this one. A single-drive sync *replaces* the map wholesale, which
///    is what makes this check load-bearing rather than defensive: syncing
///    drive B erases drive A's skip record.
///  * the last sync failed outright for this drive.
DriveStateSyncSkipStatus driveStateSyncSkipStatus({
  required String driveId,
  required SyncState syncState,
  required DateTime? lastSyncCompletedAt,
  required Set<String>? coveredDriveIds,
  required Map<String, List<String>> skippedEntityTxIdsByDrive,
}) {
  if (syncState is SyncInProgress) {
    return const DriveStateSyncSkipStatus.unknown(
      'A sync is running. Wait for it to finish, then try again.',
    );
  }

  if (syncState is SyncLoadingDrives) {
    return const DriveStateSyncSkipStatus.unknown(
      'Your drives are still loading. Wait for the sync to finish, then try '
      'again.',
    );
  }

  if (syncState is SyncCancelled) {
    return const DriveStateSyncSkipStatus.unknown(
      'The last sync was cancelled, so there is no record of what it left '
      'out. Sync this drive again, then try again.',
    );
  }

  if (syncState is SyncWalletMismatch) {
    return const DriveStateSyncSkipStatus.unknown(
      'The connected wallet changed since the last sync. Sync this drive '
      'again, then try again.',
    );
  }

  if (lastSyncCompletedAt == null) {
    return const DriveStateSyncSkipStatus.unknown(
      'No sync has finished yet, so there is nothing to confirm this drive is '
      'complete. Sync this drive, then try again.',
    );
  }

  if (coveredDriveIds != null && !coveredDriveIds.contains(driveId)) {
    return const DriveStateSyncSkipStatus.unknown(
      'The last sync did not cover this drive, so there is nothing to confirm '
      'it is complete. Sync this drive, then try again.',
    );
  }

  if (syncState is SyncCompleteWithErrors &&
      syncState.failedDriveIds.contains(driveId)) {
    return const DriveStateSyncSkipStatus.unknown(
      'The last sync failed for this drive. Sync it again, then try again.',
    );
  }

  final skipped = skippedEntityTxIdsByDrive[driveId] ?? const <String>[];
  if (skipped.isNotEmpty) {
    return DriveStateSyncSkipStatus.skipped(
      skippedEntityCount: skipped.length,
      reason: 'The last sync of this drive could not read ${skipped.length} '
          '${skipped.length == 1 ? 'item' : 'items'}. Publishing now would '
          'record that gap permanently. Sync this drive again, then try '
          'again.',
    );
  }

  return const DriveStateSyncSkipStatus.clean();
}
