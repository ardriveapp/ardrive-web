import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

/// What a sync says it examined, which is the input the publish precondition
/// rests on.
///
/// `syncAllDrives` does not sync every attached drive. The activity probe
/// asks the gateway which drives have transactions since their watermark and
/// sets the rest aside, and a drive it sets aside is not synced, not failed,
/// and named in nothing the finished report carries. A reader with only that
/// report cannot tell it from a drive that was read and found complete —
/// which is how a sweep that never opened a drive came to vouch for it.
///
/// So the report names what it opened. These tests are about that field and
/// nothing else: the drives here have no synced content, and `_syncDrive`
/// fails on the mocked DAO, which is fine because the announcement is made
/// before any drive is touched.
class _MockBatchProcessor extends Mock implements BatchProcessor {}

class _MockSnapshotValidationService extends Mock
    implements SnapshotValidationService {}

class _MockARNSRepository extends Mock implements ARNSRepository {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class _MockWallet extends Mock implements Wallet {}

class _MockDataGatewayFallback extends Mock implements DataGatewayFallback {}

class _FakeWallet extends Fake implements Wallet {}

class _FakeSecretKey extends Fake implements SecretKey {}

class _FakeSelectable<T> extends Fake implements Selectable<T> {
  final List<T> _data;

  _FakeSelectable(this._data);

  @override
  Future<List<T>> get() async => _data;

  @override
  Future<T?> getSingleOrNull() async => _data.isEmpty ? null : _data.first;

  @override
  Selectable<N> map<N>(N Function(T) f) =>
      _FakeSelectable(_data.map(f).toList());
}

Drive _drive({
  required String id,
  required String ownerAddress,
  int? lastBlockHeight,
}) =>
    Drive(
      id: id,
      rootFolderId: 'root-$id',
      ownerAddress: ownerAddress,
      name: 'Drive $id',
      lastBlockHeight: lastBlockHeight,
      privacy: 'public',
      isHidden: false,
      dateCreated: DateTime(2024),
      lastUpdated: DateTime(2024),
    );

void main() {
  const ownerAddress = 'owner-address';
  const changedDriveId = 'drive-with-activity';
  const unchangedDriveId = 'drive-the-probe-set-aside';

  late MockArweaveService arweave;
  late MockDriveDao driveDao;
  late MockConfigService configService;
  late _MockARNSRepository arnsRepository;
  late SyncRepository syncRepository;
  late _MockWallet wallet;

  setUpAll(() {
    registerFallbackValue(_FakeWallet());
    registerFallbackValue(_FakeSecretKey());
  });

  setUp(() {
    arweave = MockArweaveService();
    driveDao = MockDriveDao();
    configService = MockConfigService();
    arnsRepository = _MockARNSRepository();
    wallet = _MockWallet();

    when(() => wallet.getAddress()).thenAnswer((_) async => ownerAddress);

    when(() => configService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      // The snapshot prefetch is a separate query with its own failure modes
      // and nothing to say about which drives were examined.
      enableSyncFromSnapshot: false,
      autoSync: true,
    ));

    final gatewayFallback = _MockDataGatewayFallback();
    when(() => arweave.gatewayFallback).thenReturn(gatewayFallback);
    when(() => gatewayFallback.cachedGateways).thenReturn([]);

    when(() => arnsRepository.getAntRecordsForWallet(
          any(),
          update: any(named: 'update'),
        )).thenAnswer((_) async => <ANTRecord>[]);

    when(() => arweave.getCurrentBlockHeight()).thenAnswer((_) async => 100000);

    syncRepository = SyncRepository(
      arweave: arweave,
      driveDao: driveDao,
      configService: configService,
      batchProcessor: _MockBatchProcessor(),
      snapshotValidationService: _MockSnapshotValidationService(),
      arnsRepository: arnsRepository,
      userPreferencesRepository: _MockUserPreferencesRepository(),
    );
  });

  /// Drains a sync, keeping every progress event it managed to emit. The
  /// drives are not mocked deeply enough to sync, so the stream ends however
  /// it ends; what is under test was announced before any of that.
  Future<List<SyncProgress>> drain(Stream<SyncProgress> sync) async {
    final events = <SyncProgress>[];
    try {
      await for (final progress in sync) {
        events.add(progress);
      }
    } catch (_) {
      // Deliberately swallowed - see above.
    }
    await Future.delayed(const Duration(milliseconds: 100));
    return events;
  }

  group('syncAllDrives names the drives it opened', () {
    test('a drive the probe set aside is not among them', () async {
      when(() => driveDao.allDrives()).thenReturn(_FakeSelectable([
        _drive(
          id: changedDriveId,
          ownerAddress: ownerAddress,
          lastBlockHeight: 50000,
        ),
        _drive(
          id: unchangedDriveId,
          ownerAddress: ownerAddress,
          lastBlockHeight: 60000,
        ),
      ]));

      when(() => arweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => (
            activeDriveIds: {changedDriveId},
            isComplete: true,
          ));

      final events = await drain(syncRepository.syncAllDrives(wallet: wallet));
      final examined = events.last.examinedDriveIds;

      expect(examined, contains(changedDriveId));
      expect(
        examined,
        isNot(contains(unchangedDriveId)),
        reason: 'the probe reported no chain activity for this drive, which '
            'is not the same as a sync having read it',
      );
    });

    test('a drive the probe set aside is not reported as failed either',
        () async {
      // The half of the report that made the hole invisible. A drive that is
      // absent from `failedDriveIds` and absent from the skip map looks, to
      // anything reading only those, exactly like a drive that was read and
      // had nothing wrong with it.
      when(() => driveDao.allDrives()).thenReturn(_FakeSelectable([
        _drive(
          id: changedDriveId,
          ownerAddress: ownerAddress,
          lastBlockHeight: 50000,
        ),
        _drive(
          id: unchangedDriveId,
          ownerAddress: ownerAddress,
          lastBlockHeight: 60000,
        ),
      ]));

      when(() => arweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => (
            activeDriveIds: {changedDriveId},
            isComplete: true,
          ));

      final events = await drain(syncRepository.syncAllDrives(wallet: wallet));

      expect(
        events.every((e) => !e.failedDriveIds.contains(unchangedDriveId)),
        isTrue,
      );
      expect(
        events.every(
            (e) => !e.skippedEntityTxIdsByDrive.containsKey(unchangedDriveId)),
        isTrue,
      );
    });

    test('an incomplete probe examines every previously-synced drive',
        () async {
      // The probe reads one page of a hundred transactions; when the gateway
      // says there is another, no drive can be ruled out, and the sync opens
      // them all. The report has to say so, or the fallback would report the
      // same coverage as the skip.
      when(() => driveDao.allDrives()).thenReturn(_FakeSelectable([
        _drive(
          id: changedDriveId,
          ownerAddress: ownerAddress,
          lastBlockHeight: 50000,
        ),
        _drive(
          id: unchangedDriveId,
          ownerAddress: ownerAddress,
          lastBlockHeight: 60000,
        ),
      ]));

      when(() => arweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => (
            activeDriveIds: {changedDriveId},
            isComplete: false,
          ));

      final events = await drain(syncRepository.syncAllDrives(wallet: wallet));

      expect(
        events.last.examinedDriveIds,
        {changedDriveId, unchangedDriveId},
      );
    });

    test('a sweep in which the probe set every drive aside names nobody',
        () async {
      when(() => driveDao.allDrives()).thenReturn(_FakeSelectable([
        _drive(
          id: unchangedDriveId,
          ownerAddress: ownerAddress,
          lastBlockHeight: 60000,
        ),
      ]));

      when(() => arweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          )).thenAnswer((_) async => (
            activeDriveIds: <String>{},
            isComplete: true,
          ));

      final events = await drain(syncRepository.syncAllDrives(wallet: wallet));

      expect(
        events.last.examinedDriveIds,
        isEmpty,
        reason: 'a successful no-op sync has still read nothing',
      );
      expect(events.last.progress, 1);
    });

    test('a deep sync opens every drive, probe or no probe', () async {
      when(() => driveDao.allDrives()).thenReturn(_FakeSelectable([
        _drive(
          id: changedDriveId,
          ownerAddress: ownerAddress,
          lastBlockHeight: 50000,
        ),
        _drive(
          id: unchangedDriveId,
          ownerAddress: ownerAddress,
          lastBlockHeight: 60000,
        ),
      ]));

      final events = await drain(
        syncRepository.syncAllDrives(wallet: wallet, syncDeep: true),
      );

      expect(
        events.last.examinedDriveIds,
        {changedDriveId, unchangedDriveId},
      );
      verifyNever(() => arweave.probeActiveDriveIds(
            driveIds: any(named: 'driveIds'),
            minBlockHeight: any(named: 'minBlockHeight'),
            ownerAddress: any(named: 'ownerAddress'),
          ));
    });
  });

  group('syncSingleDrive names the drive it opened', () {
    test('the drive it was given, when that drive exists', () async {
      when(() => driveDao.driveById(driveId: any(named: 'driveId'))).thenReturn(
        _FakeSelectable([
          _drive(
            id: changedDriveId,
            ownerAddress: ownerAddress,
            lastBlockHeight: 50000,
          )
        ]),
      );

      final events = await drain(
        syncRepository.syncSingleDrive(driveId: changedDriveId, wallet: wallet),
      );

      expect(events.first.examinedDriveIds, {changedDriveId});
    });

    test('nobody, when the drive is not in the database', () async {
      // The old capture assumed the requested drive was covered because it
      // had been asked for. A drive that is not there is never opened.
      when(() => driveDao.driveById(driveId: any(named: 'driveId')))
          .thenReturn(_FakeSelectable(<Drive>[]));

      final events = await drain(
        syncRepository.syncSingleDrive(driveId: changedDriveId, wallet: wallet),
      );

      expect(events.single.examinedDriveIds, isEmpty);
    });
  });
}
