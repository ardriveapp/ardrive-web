import 'dart:async';

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drive_detail/utils/breadcrumb_builder.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/arfs/repository/drive_repository.dart';
import 'package:ardrive/gallery/explorer/explorer_view_mode.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_utils/utils.dart';

class _MockDriveRepository extends Mock implements DriveRepository {}

class _MockActivityTracker extends Mock implements ActivityTracker {}

class _MockBreadcrumbBuilder extends Mock implements BreadcrumbBuilder {}

/// The List and Gallery choice lives in the explorer's state and is kept per
/// drive on this device, so a photo drive opens as a gallery and a work drive
/// as a list.
void main() {
  setUpAll(() => registerFallbackValue(SyncTrigger.background));

  late Database db;
  late DriveDao driveDao;
  late _MockDriveRepository driveRepository;
  late MockSyncBloc syncCubit;
  late MockProfileCubit profileCubit;
  late _MockActivityTracker activityTracker;
  late _MockBreadcrumbBuilder breadcrumbBuilder;
  late MockArDriveAuth auth;
  late MockConfigService configService;
  late StreamController<SyncState> syncStates;

  Future<void> insertDrive(String driveId) async {
    final root = 'root-$driveId';
    await db.into(db.drives).insert(
          DrivesCompanion.insert(
            id: driveId,
            name: driveId,
            ownerAddress: 'owner-address',
            rootFolderId: root,
            privacy: DrivePrivacyTag.public,
            lastBlockHeight: const Value(10),
          ),
        );
    await db.into(db.folderEntries).insert(
          FolderEntriesCompanion.insert(
            id: root,
            driveId: driveId,
            name: driveId,
            path: '',
          ),
        );
    await driveDao.insertFolderRevision(
      FolderRevisionsCompanion.insert(
        folderId: root,
        driveId: driveId,
        name: driveId,
        metadataTxId: 'metadata-$driveId',
        action: RevisionAction.create,
      ),
    );
    await db.into(db.folderEntries).insert(
          FolderEntriesCompanion.insert(
            id: 'child-$driveId',
            driveId: driveId,
            parentFolderId: Value(root),
            name: 'child',
            path: '',
          ),
        );
  }

  DriveDetailCubit buildCubit(String driveId) => DriveDetailCubit(
        driveId: driveId,
        profileCubit: profileCubit,
        driveDao: driveDao,
        configService: configService,
        activityTracker: activityTracker,
        auth: auth,
        breadcrumbBuilder: breadcrumbBuilder,
        syncCubit: syncCubit,
        driveRepository: driveRepository,
      );

  Future<DriveDetailLoadSuccess> loaded(DriveDetailCubit cubit) async {
    for (var i = 0; i < 50; i++) {
      final state = cubit.state;
      if (state is DriveDetailLoadSuccess) return state;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('the drive did not load: ${cubit.state}');
  }

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // The store keeps the first preferences it was given; empty them.
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await LocalKeyValueStore.getInstance(prefs: prefs);

    db = getTestDb();
    driveDao = db.driveDao;
    driveRepository = _MockDriveRepository();
    syncCubit = MockSyncBloc();
    profileCubit = MockProfileCubit();
    activityTracker = _MockActivityTracker();
    breadcrumbBuilder = _MockBreadcrumbBuilder();
    auth = MockArDriveAuth();
    configService = MockConfigService();
    syncStates = StreamController<SyncState>.broadcast();

    when(() => driveRepository.watchDrive(driveId: any(named: 'driveId')))
        .thenAnswer((invocation) => driveDao
            .driveById(
              driveId: invocation.namedArguments[#driveId] as String,
            )
            .watchSingleOrNull());
    when(() => syncCubit.completedDriveIds).thenReturn(const []);
    when(() => syncCubit.waitCurrentSync()).thenAnswer((_) async {});
    whenListen(syncCubit, syncStates.stream, initialState: SyncIdle());
    whenListen(
      profileCubit,
      const Stream<ProfileState>.empty(),
      initialState: ProfileCheckingAvailability(),
    );
    when(() => activityTracker.isUploading).thenReturn(false);
    when(() => breadcrumbBuilder.buildForFolder(
          folderId: any(named: 'folderId'),
          rootFolderId: any(named: 'rootFolderId'),
          driveId: any(named: 'driveId'),
        )).thenAnswer((_) async => []);
  });

  tearDown(() async {
    await syncStates.close();
    await db.close();
  });

  test('a drive opens as a list until the reader chooses otherwise', () async {
    await insertDrive('photos');
    final cubit = buildCubit('photos');
    addTearDown(cubit.close);

    expect((await loaded(cubit)).viewMode, ExplorerViewMode.list);
  });

  test('choosing the gallery shows it at once and remembers it per drive',
      () async {
    await insertDrive('photos');
    await insertDrive('work');

    final photos = buildCubit('photos');
    addTearDown(photos.close);
    await loaded(photos);
    await photos.setViewMode(ExplorerViewMode.gallery);
    expect((photos.state as DriveDetailLoadSuccess).viewMode,
        ExplorerViewMode.gallery);

    // Another cubit for the same drive, as after a reload: still a gallery.
    final again = buildCubit('photos');
    addTearDown(again.close);
    expect((await loaded(again)).viewMode, ExplorerViewMode.gallery);

    // A different drive is not affected.
    final work = buildCubit('work');
    addTearDown(work.close);
    expect((await loaded(work)).viewMode, ExplorerViewMode.list);
  });

  test('choosing the list again forgets the choice', () async {
    await insertDrive('photos');
    final cubit = buildCubit('photos');
    addTearDown(cubit.close);
    await loaded(cubit);
    await cubit.setViewMode(ExplorerViewMode.gallery);
    await cubit.setViewMode(ExplorerViewMode.list);

    final store = await LocalKeyValueStore.getInstance();
    expect(store.getString(ExplorerViewModeStore.keyFor('photos')), isNull);
    final again = buildCubit('photos');
    addTearDown(again.close);
    expect((await loaded(again)).viewMode, ExplorerViewMode.list);
  });

  test('the view is part of the state\'s equality', () async {
    await insertDrive('photos');
    final cubit = buildCubit('photos');
    addTearDown(cubit.close);
    final state = await loaded(cubit);
    expect(
      state.copyWith(viewMode: ExplorerViewMode.gallery).props,
      contains(ExplorerViewMode.gallery),
    );
  });
}
