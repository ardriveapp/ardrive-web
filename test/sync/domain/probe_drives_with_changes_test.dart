import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

class _MockBatchProcessor extends Mock implements BatchProcessor {}

class _MockSnapshotValidationService extends Mock
    implements SnapshotValidationService {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class _FakeSelectable<T> extends Fake implements Selectable<T> {
  _FakeSelectable(this._data);

  final List<T> _data;

  @override
  Future<List<T>> get() async => _data;
}

Drive _drive(String id, int lastBlockHeight) => Drive(
      id: id,
      rootFolderId: 'root-$id',
      ownerAddress: 'owner',
      name: 'Drive $id',
      lastBlockHeight: lastBlockHeight,
      privacy: 'public',
      isHidden: false,
      dateCreated: DateTime(2024),
      lastUpdated: DateTime(2024),
    );

/// "N drives have changed since they were last read", asked on a fresh
/// page load: what each drive has read already must not count again.
void main() {
  late MockArweaveService arweave;
  late MockDriveDao driveDao;
  late SyncRepository repository;

  setUp(() {
    arweave = MockArweaveService();
    driveDao = MockDriveDao();
    final configService = MockConfigService();
    when(() => configService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      enableSyncFromSnapshot: false,
    ));

    // A fresh repository, as after a reload: no sync has run in it, which is
    // when a sync would look back from each drive's height.
    repository = SyncRepository(
      arweave: arweave,
      driveDao: driveDao,
      configService: configService,
      batchProcessor: _MockBatchProcessor(),
      snapshotValidationService: _MockSnapshotValidationService(),
      userPreferencesRepository: _MockUserPreferencesRepository(),
    );
  });

  test('asks from just past each drive\'s read height, with no look-back',
      () async {
    when(() => driveDao.allDrives()).thenReturn(_FakeSelectable([
      _drive('a', 1000),
      _drive('b', 2000),
    ]));
    when(() => arweave.probeActiveDriveIds(
              driveIds: any(named: 'driveIds'),
              minBlockHeight: any(named: 'minBlockHeight'),
              ownerAddress: any(named: 'ownerAddress'),
              readUpTo: any(named: 'readUpTo'),
            ))
        .thenAnswer(
            (_) async => (activeDriveIds: <String>{}, isComplete: true));

    await repository.probeDrivesWithChanges();

    final asked = verify(() => arweave.probeActiveDriveIds(
          driveIds: any(named: 'driveIds'),
          minBlockHeight: captureAny(named: 'minBlockHeight'),
          ownerAddress: 'owner',
          readUpTo: captureAny(named: 'readUpTo'),
        )).captured;
    expect(asked[0], 1001);
    expect(asked[1], {'a': 1000, 'b': 2000});
  });
}
