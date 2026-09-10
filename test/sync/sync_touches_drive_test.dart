import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which drives a running sync is allowed to hold shut.
///
/// The rule a reader feels: a sync of one drive must not lock the others, and
/// a ten-drive sync must not go on locking the drive it finished nine drives
/// ago.
void main() {
  bool touches(
    SyncState state, {
    String? syncingDriveId,
    String driveId = 'A',
    List<String> completed = const [],
    Set<String>? run,
  }) =>
      SyncCubit.syncTouchesDrive(
        state: state,
        syncingDriveId: syncingDriveId,
        driveId: driveId,
        completedDriveIds: completed,
        runDriveIds: run,
      );

  final running = SyncInProgress(trigger: SyncTrigger.userInitiated);

  group('nothing is held when nothing is running', () {
    test('idle holds nothing', () {
      expect(touches(SyncIdle()), isFalse);
    });

    test('a finished run holds nothing, whatever it completed', () {
      expect(touches(SyncIdle(), completed: ['A']), isFalse);
      expect(touches(SyncIdle(), completed: const []), isFalse);
    });
  });

  group('a single-drive sync', () {
    test('holds the drive it is walking', () {
      expect(touches(running, syncingDriveId: 'A'), isTrue);
    });

    test('and no other', () {
      expect(touches(running, syncingDriveId: 'B'), isFalse);
    });

    /// Its walk finishing is not the run finishing - ghost folders and the
    /// transaction statuses come after it. Releasing there would open the
    /// panel and quiet the row while the sync the reader pressed for is still
    /// going, which is a report contradicting itself for no gain: there is no
    /// other drive waiting on this one.
    test('holds it until the run is over, not until its walk is', () {
      expect(
        touches(running, syncingDriveId: 'A', completed: ['A']),
        isTrue,
      );
    });
  });

  group('an all-drives sync', () {
    test('holds a drive it has not reached yet', () {
      expect(touches(running, syncingDriveId: null), isTrue);
    });

    test('releases a drive it has finished walking', () {
      expect(
        touches(running, syncingDriveId: null, completed: ['A']),
        isFalse,
        reason: 'the first of ten drives must not stay shut for the other '
            'nine - its history has been read',
      );
    });

    test('and goes on holding the ones it has not', () {
      expect(
        touches(running, syncingDriveId: null, completed: ['B', 'C']),
        isTrue,
      );
    });
  });

  /// The drives table itself is what this phase writes, so a drive read by an
  /// earlier run says nothing about whether this one is about to rewrite it.
  group('while the drive list is being read', () {
    test('every drive is held', () {
      expect(touches(SyncLoadingDrives()), isTrue);
    });

    test('including one an earlier run completed', () {
      expect(
        touches(SyncLoadingDrives(), completed: ['A']),
        isTrue,
        reason: 'this phase rewrites the drive rows themselves',
      );
    });
  });

  /// A run over a chosen few carries no single drive id - it is started the
  /// same way an all-drives sync is - so without the run's own scope it would
  /// read as covering everything.
  group('a run over a chosen few', () {
    test('holds a drive it is going to walk', () {
      expect(
        touches(running, syncingDriveId: null, run: {'A', 'B'}),
        isTrue,
      );
    });

    test('and leaves the rest of the wallet alone', () {
      expect(
        touches(running, syncingDriveId: null, run: {'B', 'C'}),
        isFalse,
        reason: 'six drives must not be shut for a run over the other four',
      );
    });

    test('releases one it has already finished', () {
      expect(
        touches(
          running,
          syncingDriveId: null,
          run: {'A', 'B'},
          completed: ['A'],
        ),
        isFalse,
      );
    });
  });

  /// A drive that failed is never appended to the completed list, so it stays
  /// held for the rest of the run rather than being read as done.
  test('a failed drive is not released', () {
    expect(
      touches(running, syncingDriveId: null, completed: ['B']),
      isTrue,
      reason: 'A failed and is absent from the completed list',
    );
  });
}
