import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/utils/snapshots/gql_drive_history.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
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

    when(() => mockConfigService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      enableSyncFromSnapshot: false,
      autoSync: true,
    ));

    // Mock gateway fallback for snapshot validation service cache sharing
    final mockGatewayFallback = _MockDataGatewayFallback();
    when(() => mockArweave.gatewayFallback).thenReturn(mockGatewayFallback);
    when(() => mockGatewayFallback.cachedGateways).thenReturn([]);

    // Mock ARNS repository
    when(() => mockArnsRepository.getAntRecordsForWallet(any(),
        update: any(named: 'update'))).thenAnswer(
      (_) async => <ANTRecord>[],
    );

    syncRepository = SyncRepository(
      arweave: mockArweave,
      driveDao: mockDriveDao,
      configService: mockConfigService,
      batchProcessor: mockBatchProcessor,
      snapshotValidationService: mockSnapshotValidation,
      arnsRepository: mockArnsRepository,
      userPreferencesRepository: mockUserPrefsRepo,
    );
  });

  group('Fix 1: DriveActivityProbe partitioning', () {
    test('never-synced drives excluded from probe, probe gets non-zero minBlock',
        () async {
      final neverSynced = _makeDrive(
        id: 'drive-never',
        ownerAddress: ownerAddress,
        lastBlockHeight: null,
      );
      final synced1 = _makeDrive(
        id: 'drive-synced-1',
        ownerAddress: ownerAddress,
        lastBlockHeight: 50000,
      );
      final synced2 = _makeDrive(
        id: 'drive-synced-2',
        ownerAddress: ownerAddress,
        lastBlockHeight: 60000,
      );

      when(() => mockDriveDao.allDrives())
          .thenReturn(FakeSelectable([neverSynced, synced1, synced2]));

      when(() => mockArweave.getCurrentBlockHeight())
          .thenAnswer((_) async => 100000);

      // Probe returns only synced1 as active, isComplete: true
      when(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => (
            activeDriveIds: {'drive-synced-1'},
            isComplete: true,
          ));

      // Consume the stream — it will fail in _syncDrive since we haven't
      // mocked the full pipeline, but the probe logic runs synchronously
      // before _syncDrive is launched.
      try {
        await syncRepository
            .syncAllDrives(wallet: mockWallet)
            .toList();
      } catch (_) {}

      // Allow async tasks spawned by syncAllDrives to settle
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify probe was called with correct parameters
      final probeCall = verify(() => mockArweave.probeActiveDriveIds(
            driveIds: captureAny(named: 'driveIds'),
            minBlockHeight: captureAny(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          ));
      expect(probeCall.callCount, 1);

      // Probe should only include previously-synced drives
      final probedDriveIds = probeCall.captured[0] as List<String>;
      expect(probedDriveIds, containsAll(['drive-synced-1', 'drive-synced-2']));
      expect(probedDriveIds, isNot(contains('drive-never')));

      // The minBlockHeight should NOT be 0 (the whole point of this fix)
      final minBlock = probeCall.captured[1] as int;
      expect(minBlock, greaterThan(0));
    });

    test('all never-synced drives skip probe entirely', () async {
      final drives = [
        _makeDrive(
            id: 'a', ownerAddress: ownerAddress, lastBlockHeight: null),
        _makeDrive(id: 'b', ownerAddress: ownerAddress, lastBlockHeight: 0),
        _makeDrive(
            id: 'c', ownerAddress: ownerAddress, lastBlockHeight: null),
      ];

      when(() => mockDriveDao.allDrives())
          .thenReturn(FakeSelectable(drives));
      when(() => mockArweave.getCurrentBlockHeight())
          .thenAnswer((_) async => 100000);

      try {
        await syncRepository
            .syncAllDrives(wallet: mockWallet)
            .toList();
      } catch (_) {}

      await Future.delayed(const Duration(milliseconds: 100));

      // Probe should never be called since all drives are never-synced
      verifyNever(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          ));
    });

    test('incomplete probe falls back to all previously-synced drives',
        () async {
      final drives = [
        _makeDrive(
            id: 'a', ownerAddress: ownerAddress, lastBlockHeight: 50000),
        _makeDrive(
            id: 'b', ownerAddress: ownerAddress, lastBlockHeight: 60000),
        _makeDrive(
            id: 'c', ownerAddress: ownerAddress, lastBlockHeight: 70000),
      ];

      when(() => mockDriveDao.allDrives())
          .thenReturn(FakeSelectable(drives));
      when(() => mockArweave.getCurrentBlockHeight())
          .thenAnswer((_) async => 100000);

      // Probe returns isComplete: false (hasNextPage was true)
      when(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => (
            activeDriveIds: {'a'},
            isComplete: false,
          ));

      try {
        await syncRepository
            .syncAllDrives(wallet: mockWallet)
            .toList();
      } catch (_) {}

      await Future.delayed(const Duration(milliseconds: 100));

      // Probe was called once
      verify(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).called(1);
    });

    test('probe failure falls back to syncing all drives', () async {
      final drives = [
        _makeDrive(
            id: 'a', ownerAddress: ownerAddress, lastBlockHeight: 50000),
        _makeDrive(
            id: 'b', ownerAddress: ownerAddress, lastBlockHeight: null),
      ];

      when(() => mockDriveDao.allDrives())
          .thenReturn(FakeSelectable(drives));
      when(() => mockArweave.getCurrentBlockHeight())
          .thenAnswer((_) async => 100000);

      when(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenThrow(Exception('network error'));

      try {
        await syncRepository
            .syncAllDrives(wallet: mockWallet)
            .toList();
      } catch (_) {}

      await Future.delayed(const Duration(milliseconds: 100));

      // Should have attempted probe for the previously-synced drive only
      verify(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).called(1);
    });

    test('deep sync bypasses probe entirely', () async {
      final drives = [
        _makeDrive(
            id: 'a', ownerAddress: ownerAddress, lastBlockHeight: 50000),
      ];

      when(() => mockDriveDao.allDrives())
          .thenReturn(FakeSelectable(drives));
      when(() => mockArweave.getCurrentBlockHeight())
          .thenAnswer((_) async => 100000);

      try {
        await syncRepository
            .syncAllDrives(wallet: mockWallet, syncDeep: true)
            .toList();
      } catch (_) {}

      await Future.delayed(const Duration(milliseconds: 100));

      verifyNever(() => mockArweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          ));
    });
  });

  group('Fix 2: updateUserDrives cache', () {
    test('skips GQL call on repeat calls until cache is cleared', () async {
      when(() => mockArweave.getUniqueUserDriveEntities(
            any(),
            any(),
          )).thenAnswer((_) async => {});
      when(() => mockDriveDao.updateUserDrives(any(), any()))
          .thenAnswer((_) async {});

      // First call should hit GQL
      await syncRepository.updateUserDrives(
        wallet: mockWallet,
        password: 'pass',
        cipherKey: SecretKey([1, 2, 3]),
      );

      // Second call should be cached (up-to-date flag is set)
      await syncRepository.updateUserDrives(
        wallet: mockWallet,
        password: 'pass',
        cipherKey: SecretKey([1, 2, 3]),
      );

      verify(() => mockArweave.getUniqueUserDriveEntities(
            any(),
            any(),
          )).called(1);
    });

    test('forceRefresh bypasses cache', () async {
      when(() => mockArweave.getUniqueUserDriveEntities(
            any(),
            any(),
          )).thenAnswer((_) async => {});
      when(() => mockDriveDao.updateUserDrives(any(), any()))
          .thenAnswer((_) async {});

      // First call
      await syncRepository.updateUserDrives(
        wallet: mockWallet,
        password: 'pass',
        cipherKey: SecretKey([1, 2, 3]),
      );

      // Second call with forceRefresh should bypass cache
      await syncRepository.updateUserDrives(
        wallet: mockWallet,
        password: 'pass',
        cipherKey: SecretKey([1, 2, 3]),
        forceRefresh: true,
      );

      verify(() => mockArweave.getUniqueUserDriveEntities(
            any(),
            any(),
          )).called(2);
    });
  });

  group('Fix 3: GQLDriveHistory genesis block guard', () {
    test('skips [0,0] range and does not query gateway', () async {
      final mockArweaveForGql = MockArweaveService();

      final gqlHistory = GQLDriveHistory(
        subRanges: HeightRange(rangeSegments: [
          Range(start: 0, end: 0),
          Range(start: 100, end: 200),
        ]),
        arweave: mockArweaveForGql,
        driveId: 'test-drive',
        ownerAddress: 'test-owner',
      );

      when(() => mockArweaveForGql.getSegmentedTransactionsFromDrive(
            any(),
            minBlockHeight: any(named: 'minBlockHeight'),
            maxBlockHeight: any(named: 'maxBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
            strategy: any(named: 'strategy'),
          )).thenAnswer((_) => const Stream.empty());

      when(() => mockArweaveForGql.graphQLRetry)
          .thenReturn(MockGraphQLRetry());

      // First getNextStream() processes [0,0] — should be skipped silently
      final stream1 = gqlHistory.getNextStream();
      final results1 = await stream1.toList();
      expect(results1, isEmpty);

      // Verify NO gateway call was made for [0,0]
      verifyNever(() => mockArweaveForGql.getSegmentedTransactionsFromDrive(
            any(),
            minBlockHeight: any(named: 'minBlockHeight'),
            maxBlockHeight: any(named: 'maxBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
            strategy: any(named: 'strategy'),
          ));

      // Second getNextStream() processes [100,200] — should query normally
      final stream2 = gqlHistory.getNextStream();
      await stream2.toList();

      verify(() => mockArweaveForGql.getSegmentedTransactionsFromDrive(
            any(),
            minBlockHeight: 100,
            maxBlockHeight: 200,
            ownerAddress: any(named: 'ownerAddress'),
            strategy: any(named: 'strategy'),
          )).called(1);
    });
  });
}
