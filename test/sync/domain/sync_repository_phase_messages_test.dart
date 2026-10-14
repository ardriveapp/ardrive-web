import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

// Mocks not available in shared mocks file
class MockBatchProcessor extends Mock implements BatchProcessor {}

class MockSnapshotValidationService extends Mock
    implements SnapshotValidationService {}

class _MockARNSRepository extends Mock implements ARNSRepository {}

class MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class _MockWallet extends Mock implements Wallet {}

class _MockDataGatewayFallback extends Mock implements DataGatewayFallback {}

class _FakeWallet extends Fake implements Wallet {}

class _FakeSecretKey extends Fake implements SecretKey {}

class FakeSelectable<T> extends Fake implements Selectable<T> {
  final List<T> _data;
  FakeSelectable(this._data);

  @override
  Future<List<T>> get() async => _data;

  @override
  Future<T> getSingle() async => _data.single;

  @override
  Future<T?> getSingleOrNull() async => _data.isEmpty ? null : _data.single;

  @override
  Selectable<N> map<N>(N Function(T) f) {
    return FakeSelectable(_data.map(f).toList());
  }
}

// Helper to create a Drive with specific fields
Drive _makeDrive({
  required String id,
  required String ownerAddress,
  int? lastBlockHeight,
  String name = 'Test Drive',
}) {
  return Drive(
    id: id,
    rootFolderId: 'root-$id',
    ownerAddress: ownerAddress,
    name: name,
    lastBlockHeight: lastBlockHeight,
    privacy: 'public',
    isHidden: false,
    dateCreated: DateTime(2024),
    lastUpdated: DateTime(2024),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeWallet());
    registerFallbackValue(_FakeSecretKey());
  });

  late MockArweaveService mockArweave;
  late MockDriveDao mockDriveDao;
  late MockConfigService mockConfigService;
  late MockBatchProcessor mockBatchProcessor;
  late MockSnapshotValidationService mockSnapshotValidation;
  late _MockARNSRepository mockArnsRepository;
  late MockUserPreferencesRepository mockUserPrefsRepo;
  late SyncRepository syncRepository;
  late _MockWallet mockWallet;

  const ownerAddress = 'owner-address-123';

  const connecting = 'Connecting to the network...';
  const checking = 'Checking for changes...';
  const downloading = 'Downloading drive snapshots...';
  const readingHistory = 'Reading the drive history...';

  /// Configures the repository. Snapshot prefetch is off by default, matching
  /// the other sync repository tests; the prefetch group turns it on.
  void buildRepository({bool enableSyncFromSnapshot = false}) {
    when(() => mockConfigService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      enableSyncFromSnapshot: enableSyncFromSnapshot,
      autoSync: true,
    ));

    syncRepository = SyncRepository(
      arweave: mockArweave,
      driveDao: mockDriveDao,
      configService: mockConfigService,
      batchProcessor: mockBatchProcessor,
      snapshotValidationService: mockSnapshotValidation,
      arnsRepository: mockArnsRepository,
      userPreferencesRepository: mockUserPrefsRepo,
    );
  }

  /// Stubs everything a drive walk and the post-sync phase touch, so the
  /// listed drives actually sync to completion and the stream reaches its
  /// 'Sync complete' emission. Each drive walks an empty transaction stream.
  void stubSuccessfulDriveSync(List<Drive> drives) {
    for (final drive in drives) {
      when(() => mockDriveDao.driveById(driveId: drive.id))
          .thenReturn(FakeSelectable([drive]));
      when(() => mockDriveDao.pendingTransactionsForDrive(driveId: drive.id))
          .thenReturn(FakeSelectable(<NetworkTransaction>[]));
    }

    when(() => mockArweave.getSegmentedTransactionsFromDrive(
          any(),
          ownerAddress: any(named: 'ownerAddress'),
          minBlockHeight: any(named: 'minBlockHeight'),
          maxBlockHeight: any(named: 'maxBlockHeight'),
          strategy: any(named: 'strategy'),
        )).thenAnswer((_) => const Stream.empty());
    when(() => mockArweave.snapshotMetadataHits).thenReturn(<String, int>{});
    when(() => mockArweave.snapshotMetadataMisses).thenReturn(<String, int>{});
    when(() => mockArweave.clearUserDriveTxsCache()).thenReturn(null);

    // Post-sync phase.
    when(() => mockArnsRepository.waitForARNSRecordsToUpdate())
        .thenAnswer((_) async {});
    when(() => mockArnsRepository.saveAllFilesWithAssignedNames())
        .thenAnswer((_) async {});
    when(() => mockDriveDao.hasHiddenItems())
        .thenReturn(FakeSelectable([false]));
    when(() => mockUserPrefsRepo.saveUserHasHiddenItem(any()))
        .thenAnswer((_) async {});
    when(() => mockUserPrefsRepo.load()).thenAnswer(
      (_) async => const UserPreferences(
        currentTheme: ArDriveThemes.light,
        lastSelectedDriveId: null,
      ),
    );
    when(() => mockDriveDao.pinnedFileRevisions())
        .thenReturn(FakeSelectable(<FileRevision>[]));
    when(() => mockDriveDao.pendingDataFileRevisions())
        .thenReturn(FakeSelectable(<FileRevision>[]));
    when(() => mockDriveDao.pendingTransactions())
        .thenReturn(FakeSelectable(<NetworkTransaction>[]));
  }

  /// Runs a full sync to exhaustion and returns everything it emitted. Unless
  /// [stubSuccessfulDriveSync] was called, the drive walk is not mocked, so
  /// each drive fails inside `_syncDrive` after the phases under test have
  /// already been announced.
  Future<List<SyncProgress>> collectProgress({bool syncDeep = false}) async {
    final emitted = <SyncProgress>[];

    try {
      await for (final progress in syncRepository.syncAllDrives(
        wallet: mockWallet,
        syncDeep: syncDeep,
      )) {
        emitted.add(progress);
      }
    } catch (_) {}

    // Allow async tasks spawned by syncAllDrives to settle
    await Future.delayed(const Duration(milliseconds: 100));

    return emitted;
  }

  Future<List<SyncProgress>> collectSingleDriveProgress(String driveId) async {
    final emitted = <SyncProgress>[];

    try {
      await for (final progress in syncRepository.syncSingleDrive(
        driveId: driveId,
        wallet: mockWallet,
      )) {
        emitted.add(progress);
      }
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 100));

    return emitted;
  }

  List<String> statusMessagesOf(List<SyncProgress> emitted) =>
      emitted.map((p) => p.statusMessage).whereType<String>().toList();

  setUp(() {
    mockArweave = MockArweaveService();
    mockDriveDao = MockDriveDao();
    mockConfigService = MockConfigService();
    mockBatchProcessor = MockBatchProcessor();
    mockSnapshotValidation = MockSnapshotValidationService();
    mockArnsRepository = _MockARNSRepository();
    mockUserPrefsRepo = MockUserPreferencesRepository();
    mockWallet = _MockWallet();

    when(() => mockWallet.getAddress()).thenAnswer((_) async => ownerAddress);

    // Mock gateway fallback for snapshot validation service cache sharing
    final mockGatewayFallback = _MockDataGatewayFallback();
    when(() => mockArweave.gatewayFallback).thenReturn(mockGatewayFallback);
    when(() => mockGatewayFallback.cachedGateways).thenReturn([]);

    // Mock ARNS repository
    when(() => mockArnsRepository.getAntRecordsForWallet(any(),
        update: any(named: 'update'))).thenAnswer(
      (_) async => <ANTRecord>[],
    );

    when(() => mockArweave.getCurrentBlockHeight())
        .thenAnswer((_) async => 100000);

    buildRepository();
  });

  group('phase status messages', () {
    test('names the block height fetch', () async {
      when(() => mockDriveDao.allDrives()).thenReturn(FakeSelectable([
        _makeDrive(id: 'a', ownerAddress: ownerAddress, lastBlockHeight: 50000),
      ]));
      when(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => (
            activeDriveIds: {'a'},
            isComplete: true,
          ));

      final messages = statusMessagesOf(await collectProgress());

      expect(messages, contains(connecting));
    });

    test('the block height message is announced before the probe', () async {
      when(() => mockDriveDao.allDrives()).thenReturn(FakeSelectable([
        _makeDrive(id: 'a', ownerAddress: ownerAddress, lastBlockHeight: 50000),
      ]));
      when(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => (
            activeDriveIds: {'a'},
            isComplete: true,
          ));

      final messages = statusMessagesOf(await collectProgress());

      // Both must be present before their order means anything: indexOf
      // returns -1 for a missing message, and -1 < 0 would pass vacuously.
      expect(messages, contains(connecting));
      expect(messages, contains(checking));
      expect(
        messages.indexOf(connecting),
        lessThan(messages.indexOf(checking)),
      );
    });

    test('names the snapshot prefetch', () async {
      buildRepository(enableSyncFromSnapshot: true);

      when(() => mockDriveDao.allDrives()).thenReturn(FakeSelectable([
        _makeDrive(id: 'a', ownerAddress: ownerAddress, lastBlockHeight: 50000),
      ]));
      when(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => (
            activeDriveIds: {'a'},
            isComplete: true,
          ));
      when(() => mockArweave.getAllSnapshotsForDrives(
            any(),
            any(),
            ownerAddress: any(named: 'ownerAddress'),
            onQueryFailure: any(named: 'onQueryFailure'),
          )).thenAnswer((_) => const Stream.empty());

      final messages = statusMessagesOf(await collectProgress());

      expect(messages, contains(downloading));
    });

    test('says nothing about snapshots when the prefetch does not run',
        () async {
      when(() => mockDriveDao.allDrives()).thenReturn(FakeSelectable([
        _makeDrive(id: 'a', ownerAddress: ownerAddress, lastBlockHeight: 50000),
      ]));
      when(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => (
            activeDriveIds: {'a'},
            isComplete: true,
          ));

      final messages = statusMessagesOf(await collectProgress());

      expect(messages, isNot(contains(downloading)));
    });

    test('says nothing during the drive walk, so the percentage stays up',
        () async {
      // The dialog renders statusMessage INSTEAD OF the "{n}% complete"
      // readout (app_shell.dart, `if (statusMessage != null) ... else ...`).
      // A message set during the walk would blank the only number the user
      // sees for the whole length of the walk, so the walk must stay silent.
      final drive = _makeDrive(
        id: 'a',
        ownerAddress: ownerAddress,
        lastBlockHeight: 50000,
        name: 'Photos',
      );
      when(() => mockDriveDao.allDrives()).thenReturn(FakeSelectable([drive]));
      when(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => (
            activeDriveIds: {'a'},
            isComplete: true,
          ));
      stubSuccessfulDriveSync([drive]);

      final emitted = await collectProgress();

      // The walk is the stretch before the post-sync phases announce
      // themselves - it ends where ghost folder creation begins. Bounding it
      // by a progress value instead would pin this test to whatever share of
      // the bar the walk currently owns, which is not what it is about.
      final tailStart = emitted
          .indexWhere((p) => p.statusMessage == 'Creating ghost folders...');
      final walk = emitted
          .sublist(0, tailStart == -1 ? emitted.length : tailStart)
          .where((p) => p.progress > 0)
          .toList();
      expect(walk, isNotEmpty);
      expect(walk.every((p) => p.statusMessage == null), isTrue);
      expect(
        statusMessagesOf(emitted).where((m) => m.contains('Photos')),
        isEmpty,
      );
    });

    test('emits exactly the phase messages this sync has, in order', () async {
      buildRepository(enableSyncFromSnapshot: true);

      when(() => mockDriveDao.allDrives()).thenReturn(FakeSelectable([
        _makeDrive(
          id: 'a',
          ownerAddress: ownerAddress,
          lastBlockHeight: 50000,
          name: 'Photos',
        ),
      ]));
      when(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => (
            activeDriveIds: {'a'},
            isComplete: true,
          ));
      when(() => mockArweave.getAllSnapshotsForDrives(
            any(),
            any(),
            ownerAddress: any(named: 'ownerAddress'),
            onQueryFailure: any(named: 'onQueryFailure'),
          )).thenAnswer((_) => const Stream.empty());

      final messages = statusMessagesOf(await collectProgress());

      // The exact set, not merely "non-empty": this drive fails its walk, so
      // the three pre-walk phases are the whole of what this sync says.
      expect(messages, [connecting, checking, downloading]);
    });
  });

  group('drive counts on SyncProgress', () {
    test('reports how many drives need a first-time sync', () async {
      when(() => mockDriveDao.allDrives()).thenReturn(FakeSelectable([
        _makeDrive(id: 'a', ownerAddress: ownerAddress, lastBlockHeight: null),
        _makeDrive(id: 'b', ownerAddress: ownerAddress, lastBlockHeight: 0),
      ]));

      final emitted = await collectProgress();

      expect(emitted.last.firstTimeSyncDriveCount, 2);
      expect(emitted.last.skippedDriveCount, 0);
    });

    test('reports how many unchanged drives the probe skipped', () async {
      when(() => mockDriveDao.allDrives()).thenReturn(FakeSelectable([
        _makeDrive(id: 'a', ownerAddress: ownerAddress, lastBlockHeight: 50000),
        _makeDrive(id: 'b', ownerAddress: ownerAddress, lastBlockHeight: 60000),
        _makeDrive(id: 'c', ownerAddress: ownerAddress, lastBlockHeight: null),
      ]));
      when(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => (
            activeDriveIds: <String>{},
            isComplete: true,
          ));

      final emitted = await collectProgress();

      // Only the never-synced drive is left to sync.
      expect(emitted.last.skippedDriveCount, 2);
      expect(emitted.last.firstTimeSyncDriveCount, 1);
    });

    test('a sync with nothing to do still reports what it skipped', () async {
      when(() => mockDriveDao.allDrives()).thenReturn(FakeSelectable([
        _makeDrive(id: 'a', ownerAddress: ownerAddress, lastBlockHeight: 50000),
        _makeDrive(id: 'b', ownerAddress: ownerAddress, lastBlockHeight: 60000),
      ]));
      when(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => (
            activeDriveIds: <String>{},
            isComplete: true,
          ));

      final emitted = await collectProgress();

      expect(emitted.last.progress, 1);
      expect(emitted.last.skippedDriveCount, 2);
      expect(emitted.last.firstTimeSyncDriveCount, 0);
    });

    test('a deep sync reads every drive from the start and skips nothing',
        () async {
      when(() => mockDriveDao.allDrives()).thenReturn(FakeSelectable([
        _makeDrive(id: 'a', ownerAddress: ownerAddress, lastBlockHeight: 50000),
        _makeDrive(id: 'b', ownerAddress: ownerAddress, lastBlockHeight: null),
      ]));

      final emitted = await collectProgress(syncDeep: true);

      // A deep sync rewinds every drive to block zero, watermark or not, so
      // both count as first-time walks. Nothing is probed, nothing skipped.
      expect(emitted.last.firstTimeSyncDriveCount, 2);
      expect(emitted.last.skippedDriveCount, 0);
    });

    test('a failed probe still reports the drives read from the start',
        () async {
      when(() => mockDriveDao.allDrives()).thenReturn(FakeSelectable([
        _makeDrive(id: 'a', ownerAddress: ownerAddress, lastBlockHeight: 50000),
        _makeDrive(id: 'b', ownerAddress: ownerAddress, lastBlockHeight: null),
        _makeDrive(id: 'c', ownerAddress: ownerAddress, lastBlockHeight: 0),
      ]));
      when(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenThrow(Exception('gateway is down'));

      final emitted = await collectProgress();

      // The probe could not answer, so all three sync and none is skipped -
      // but only the two never-synced drives walk from the start.
      expect(emitted.last.firstTimeSyncDriveCount, 2);
      expect(emitted.last.skippedDriveCount, 0);
    });

    test('the counts survive to a successful "Sync complete"', () async {
      final active = _makeDrive(
          id: 'a', ownerAddress: ownerAddress, lastBlockHeight: 50000);
      final unchanged = _makeDrive(
          id: 'b', ownerAddress: ownerAddress, lastBlockHeight: 60000);
      final neverSynced = _makeDrive(
          id: 'c', ownerAddress: ownerAddress, lastBlockHeight: null);

      when(() => mockDriveDao.allDrives())
          .thenReturn(FakeSelectable([active, unchanged, neverSynced]));
      when(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => (
            activeDriveIds: {'a'},
            isComplete: true,
          ));
      stubSuccessfulDriveSync([active, neverSynced]);

      final emitted = await collectProgress();
      final last = emitted.last;

      // The terminal emission a summary UI reads: not an early return, but the
      // one the post-sync phase publishes after every drive walked cleanly.
      expect(last.statusMessage, 'Sync complete');
      expect(last.progress, 1.0);
      expect(last.firstTimeSyncDriveCount, 1);
      expect(last.skippedDriveCount, 1);
    });
  });

  group('syncSingleDrive', () {
    test('names the wait for this drive history instead of showing a nought',
        () async {
      // This is the emission the user sits on for the whole first GraphQL
      // round trip, which on a never-walked drive is the longest single wait
      // in the sync. It used to carry no message and no measurement, and the
      // panel falls through to the percentage when there is no phase - so it
      // read "0% complete", motionless, for as long as the gateway took. That
      // is the exact thing this series exists to stop.
      final drive = _makeDrive(
        id: 'a',
        ownerAddress: ownerAddress,
        lastBlockHeight: 50000,
        name: 'Photos',
      );
      when(() => mockDriveDao.driveById(driveId: 'a'))
          .thenReturn(FakeSelectable([drive]));

      final emitted = await collectSingleDriveProgress('a');

      final connectingIndex =
          emitted.indexWhere((p) => p.statusMessage == connecting);
      expect(connectingIndex, isNonNegative);

      expect(emitted.length, greaterThan(connectingIndex + 1));

      // The walk fails, so the emission published before it is the last one -
      // and it is the one that was on screen.
      // The emission left on screen for the length of the round trip.
      final beforeTheWalk = emitted[connectingIndex + 1];
      expect(
        beforeTheWalk.statusMessage,
        readingHistory,
        reason: 'the wait before the walk has to say what it is waiting for',
      );
      expect(
        beforeTheWalk.isIndeterminate,
        true,
        reason: 'nothing has measured anything yet, so the bar must sweep '
            'rather than draw a figure the sync does not have',
      );
      expect(beforeTheWalk.progress, 0);

      expect(statusMessagesOf(emitted), [connecting, readingHistory]);

      // And nothing after the block height is a bare nought: no phase to
      // name, nothing indeterminate, and a figure of zero - which is exactly
      // what the panel renders as a motionless "0% complete".
      expect(
        emitted.skip(connectingIndex).where((p) =>
            p.progress == 0 && p.statusMessage == null && !p.isIndeterminate),
        isEmpty,
      );
    });

    test('hands the walk back to the percentage the moment it measures one',
        () async {
      // The named phase and the sweeping bar are for the stretch with nothing
      // to measure and no longer: once the walk reports a fraction of its own
      // there is a number worth showing, and the panel draws the phase in
      // preference to the number whenever there is one. A message that
      // survived into the walk would blank the percentage for the whole of it,
      // which is the mirror image of the bug this replaced.
      final drive = _makeDrive(
        id: 'a',
        ownerAddress: ownerAddress,
        lastBlockHeight: 50000,
        name: 'Photos',
      );
      when(() => mockDriveDao.driveById(driveId: 'a'))
          .thenReturn(FakeSelectable([drive]));
      stubSuccessfulDriveSync([drive]);

      final emitted = await collectSingleDriveProgress('a');

      final ghosts = emitted
          .indexWhere((p) => p.statusMessage == 'Creating ghost folders...');
      expect(ghosts, isNonNegative,
          reason: 'the fixture never got past the walk');

      // The walk's own emissions: it has measured something, and it has not
      // yet reported the drive done.
      final walk = emitted
          .sublist(0, ghosts)
          .where((p) => p.progress > 0 && p.drivesSynced == 0)
          .toList();

      expect(walk, isNotEmpty,
          reason: 'the fixture never measured anything, so nothing below is '
              'about a measured walk');
      expect(
        walk.every((p) => p.statusMessage == null),
        true,
        reason: 'the walk has a percentage now, and the panel shows a phase '
            'in preference to it',
      );
      expect(
        walk.every((p) => !p.isIndeterminate),
        true,
        reason: 'a bar told it cannot measure this will sweep past a figure '
            'the walk is publishing',
      );

      // And the walk's last word is a number, not a sweep.
      final walkEnded = emitted[ghosts - 1];
      expect(walkEnded.drivesSynced, 1);
      expect(walkEnded.statusMessage, null);
      expect(walkEnded.isIndeterminate, false);
    });

    test('reports the drive as first-time when it has never been synced',
        () async {
      // The count has to mean the same thing on this path as on the
      // all-drives one, because the UI reading it cannot tell which sync
      // produced the number it is holding.
      final never = _makeDrive(
        id: 'a',
        ownerAddress: ownerAddress,
        lastBlockHeight: 0,
        name: 'Fresh',
      );
      when(() => mockDriveDao.driveById(driveId: 'a'))
          .thenReturn(FakeSelectable([never]));

      final emitted = await collectSingleDriveProgress('a');

      expect(emitted.first.firstTimeSyncDriveCount, 1);
    });

    test('reports no first-time drive when it has a watermark', () async {
      final synced = _makeDrive(
        id: 'a',
        ownerAddress: ownerAddress,
        lastBlockHeight: 50000,
        name: 'Photos',
      );
      when(() => mockDriveDao.driveById(driveId: 'a'))
          .thenReturn(FakeSelectable([synced]));

      final emitted = await collectSingleDriveProgress('a');

      expect(emitted.first.firstTimeSyncDriveCount, 0);
    });
  });
}
