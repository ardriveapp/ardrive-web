import 'package:ardrive/blocs/fs_entry_snapshots/fs_entry_snapshots_cubit.dart';
import 'package:ardrive/blocs/fs_entry_snapshots/models/snapshot_display_item.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/models/enums.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/snapshot_events.dart';
import 'package:ardrive/utils/snapshots/snapshots_cache.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

const _owner = 'owner-address';

class _Discovery implements DriveStateDiscovery {
  _Discovery(this.result);

  final DriveStateDiscoveryResult result;
  int calls = 0;

  @override
  Future<DriveStateDiscoveryResult> findCandidates({
    required String driveId,
    required String ownerAddress,
    int? minBlockHeight,
  }) async {
    calls++;
    return result;
  }
}

/// Users see one term for both kinds of snapshot, so the Snapshots tab lists
/// a drive's drive state artifacts beside its older snapshots.
void main() {
  late MockArweaveService arweave;
  var driveCount = 0;
  late String driveId;

  setUp(() {
    arweave = MockArweaveService();
    SnapshotsCache.instance.clear();
    driveId = 'drive-${driveCount++}';
  });

  void olderSnapshots(List<({String txId, int minedAtSeconds})> found) {
    when(() => arweave.getAllSnapshotsOfDrive(any(), any(),
        ownerAddress: any(named: 'ownerAddress'))).thenAnswer(
      (_) => Stream.fromIterable(found.map(
        (s) => SnapshotEntityTransaction.fromJson({
          'id': s.txId,
          'owner': {'address': _owner},
          'tags': [
            {'name': 'Block-Start', 'value': '0'},
            {'name': 'Block-End', 'value': '100'},
            {'name': 'Drive-Id', 'value': driveId},
            {'name': EntityTag.entityType, 'value': EntityTypeTag.snapshot},
          ],
          'block': {'height': 100, 'timestamp': s.minedAtSeconds},
        }),
      )),
    );
  }

  DriveStateArtifactCandidate artifact(
    String txId, {
    int? minedAtSeconds,
    int unixTime = 5000,
  }) =>
      DriveStateArtifactCandidate(
        txId: txId,
        ownerAddress: _owner,
        tags: {
          'Drive-Id': driveId,
          'Block-Start': '0',
          'Block-End': '2021868',
          'Unix-Time': '$unixTime',
        },
        minedAtHeight: minedAtSeconds == null ? null : 2021870,
        minedAtTimestamp: minedAtSeconds,
      );

  Future<FsEntrySnapshotsSuccess> loaded(FsEntrySnapshotsCubit cubit) async {
    final state = await cubit.stream.firstWhere(
      (s) => s is FsEntrySnapshotsSuccess || s is FsEntrySnapshotsFailure,
    );
    expect(state, isA<FsEntrySnapshotsSuccess>());
    return state as FsEntrySnapshotsSuccess;
  }

  test('lists drive state artifacts beside older snapshots, newest first',
      () async {
    olderSnapshots([
      (txId: 'old-snapshot', minedAtSeconds: 1000),
      (txId: 'newer-snapshot', minedAtSeconds: 3000),
    ]);
    final discovery = _Discovery(DriveStateDiscoveryResult(candidates: [
      artifact('mined-artifact', minedAtSeconds: 2000),
      artifact('pending-artifact', unixTime: 4000),
    ]));

    final cubit = FsEntrySnapshotsCubit(
      driveId: driveId,
      ownerAddress: _owner,
      arweaveService: arweave,
      driveStateDiscovery: discovery,
    );
    final state = await loaded(cubit);

    expect(state.snapshots.map((s) => s.txId), [
      'pending-artifact',
      'newer-snapshot',
      'mined-artifact',
      'old-snapshot',
    ]);
    final mined = state.snapshots.firstWhere((s) => s.txId == 'mined-artifact');
    expect(mined.status, TransactionStatus.confirmed);
    expect(mined.blockStart, 0);
    expect(mined.blockEnd, 2021868);
    expect(mined.createdAt, DateTime.fromMillisecondsSinceEpoch(2000 * 1000));
    // Not mined yet: dated by its own Unix-Time tag, and shown as pending
    // rather than as a snapshot anyone can already load from.
    final pending =
        state.snapshots.firstWhere((s) => s.txId == 'pending-artifact');
    expect(pending.status, TransactionStatus.pending);
    expect(pending.createdAt, DateTime.fromMillisecondsSinceEpoch(4000 * 1000));

    await cubit.close();
  });

  test('lists older snapshots only where the build has no artifacts', () async {
    olderSnapshots([(txId: 'old-snapshot', minedAtSeconds: 1000)]);

    final cubit = FsEntrySnapshotsCubit(
      driveId: driveId,
      ownerAddress: _owner,
      arweaveService: arweave,
    );
    final state = await loaded(cubit);

    expect(state.snapshots.map((s) => s.txId), ['old-snapshot']);
    await cubit.close();
  });

  test('a failed artifact lookup still lists the older snapshots', () async {
    olderSnapshots([(txId: 'old-snapshot', minedAtSeconds: 1000)]);
    final discovery = _Discovery(const DriveStateDiscoveryResult.failed());

    final cubit = FsEntrySnapshotsCubit(
      driveId: driveId,
      ownerAddress: _owner,
      arweaveService: arweave,
      driveStateDiscovery: discovery,
    );
    final state = await loaded(cubit);

    expect(discovery.calls, 1);
    expect(state.snapshots.map((s) => s.txId), ['old-snapshot']);
    await cubit.close();
  });

  // Creating a snapshot resets the drive's count before announcing it, as the
  // older snapshot dialog's DriveSnapshotted does, so the tab that lists the
  // new snapshot stops recommending one in the same update.
  test('a snapshot created from the tab clears "Snapshot recommended"',
      () async {
    olderSnapshots([]);
    CountOfTxsSyncedWithGql.countForDrive(
      driveId,
      defaultNumberOfTxsBeforeSnapshot,
    );
    final cubit = FsEntrySnapshotsCubit(
      driveId: driveId,
      ownerAddress: _owner,
      arweaveService: arweave,
    );
    expect((await loaded(cubit)).shouldRecommendSnapshot, isTrue);

    final next = cubit.stream.first;
    CountOfTxsSyncedWithGql.resetForDrive(driveId);
    SnapshotEventBus.instance.emitSnapshotCreated(SnapshotDisplayItem(
      txId: 'just-created',
      driveId: driveId,
      blockStart: 0,
      blockEnd: 100,
      createdAt: DateTime.now(),
      status: TransactionStatus.pending,
    ));

    final state = await next as FsEntrySnapshotsSuccess;
    expect(state.snapshots.map((s) => s.txId), ['just-created']);
    expect(state.shouldRecommendSnapshot, isFalse);
    SnapshotEventBus.instance.consumePendingSnapshot(driveId, 'just-created');
    await cubit.close();
  });
}
