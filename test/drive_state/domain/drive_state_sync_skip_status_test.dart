import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where "the last sync reported nothing skipped" is turned into "this drive
/// is safe to publish" — and every case where that inference is not available.
///
/// The empty map [SyncCubit] starts with reads exactly like a clean report,
/// and a scoped sync replaces the map wholesale, so silence about a drive is
/// only evidence when it is known which drives the report covered. Everything
/// else answers `unknown`, and the creation service refuses on it.
void main() {
  const driveId = 'drive-id';
  const otherDriveId = 'other-drive-id';

  final completedAt = DateTime(2026, 8, 19);

  DriveStateSyncSkipStatus statusOf({
    SyncState? syncState,
    DateTime? lastSyncCompletedAt,
    Set<String>? coveredDriveIds,
    Map<String, List<String>> skipped = const {},
    String id = driveId,
  }) =>
      driveStateSyncSkipStatus(
        driveId: id,
        syncState: syncState ?? SyncIdle(),
        lastSyncCompletedAt: lastSyncCompletedAt ?? completedAt,
        coveredDriveIds: coveredDriveIds,
        skippedEntityTxIdsByDrive: skipped,
      );

  group('clean', () {
    test('a completed sweep that reported nothing skipped', () {
      expect(statusOf().state, DriveStateSyncSkipState.clean);
    });

    test('a completed sync that skipped entities on a different drive', () {
      final status = statusOf(
        skipped: const {
          otherDriveId: ['tx-1'],
        },
      );

      expect(status.state, DriveStateSyncSkipState.clean);
    });

    test('a scoped sync that did cover this drive', () {
      final status = statusOf(coveredDriveIds: {driveId, otherDriveId});

      expect(status.state, DriveStateSyncSkipState.clean);
    });
  });

  group('skipped', () {
    test('reports the count, and says what to do about it', () {
      final status = statusOf(
        skipped: const {
          driveId: ['tx-1', 'tx-2', 'tx-3'],
        },
      );

      expect(status.state, DriveStateSyncSkipState.skipped);
      expect(status.skippedEntityCount, 3);
      expect(status.reason, contains('3 items'));
      expect(status.reason, contains('Sync this drive again'));
    });

    test('one skipped entity is still a gap', () {
      final status = statusOf(
        skipped: const {
          driveId: ['tx-1'],
        },
      );

      expect(status.state, DriveStateSyncSkipState.skipped);
      expect(status.reason, contains('1 item'));
    });
  });

  group('unknown, because the report cannot be read as evidence', () {
    void expectUnknown(DriveStateSyncSkipStatus status) {
      expect(status.state, DriveStateSyncSkipState.unknown);
      expect(status.isClean, isFalse);
      expect(status.reason, isNotEmpty);
    }

    test('no sync has finished in this session', () {
      // Called directly rather than through the helper, because the case is
      // precisely a null completion time. The empty map is what the cubit
      // starts with; without a timestamp beside it, it is indistinguishable
      // from a clean report, which is the whole reason this case exists.
      expectUnknown(driveStateSyncSkipStatus(
        driveId: driveId,
        syncState: SyncIdle(),
        lastSyncCompletedAt: null,
        coveredDriveIds: null,
        skippedEntityTxIdsByDrive: const {},
      ));
    });

    test('a sync is running', () {
      expectUnknown(statusOf(syncState: SyncInProgress()));
    });

    test('drives are still loading', () {
      expectUnknown(statusOf(syncState: SyncLoadingDrives()));
    });

    test('the last sync was cancelled before it could report', () {
      expectUnknown(statusOf(
        syncState: SyncCancelled(
          drivesCompleted: 1,
          totalDrives: 2,
          cancelledAt: completedAt,
        ),
      ));
    });

    test('the wallet changed since the last sync', () {
      expectUnknown(statusOf(syncState: SyncWalletMismatch()));
    });

    test('the last sync covered other drives, not this one', () {
      // A single-drive sync of another drive replaces the skip map wholesale,
      // erasing whatever an earlier sync recorded for this one.
      expectUnknown(statusOf(coveredDriveIds: {otherDriveId}));
    });

    test('the last sync failed for this drive', () {
      expectUnknown(statusOf(
        syncState: SyncCompleteWithErrors(
          failedDrives: 1,
          totalDrives: 2,
          failedDriveIds: const [driveId],
          errorMessages: const {driveId: 'boom'},
        ),
      ));
    });

    test('a sync that failed for another drive says nothing about this one',
        () {
      final status = statusOf(
        syncState: SyncCompleteWithErrors(
          failedDrives: 1,
          totalDrives: 2,
          failedDriveIds: const [otherDriveId],
          errorMessages: const {otherDriveId: 'boom'},
        ),
      );

      expect(status.state, DriveStateSyncSkipState.clean);
    });
  });
}
