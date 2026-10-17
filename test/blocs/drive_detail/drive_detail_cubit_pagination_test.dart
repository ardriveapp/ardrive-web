import 'dart:async';

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drive_detail/utils/breadcrumb_builder.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/arfs/repository/drive_repository.dart';
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

/// The file table's page memory, page size and "show this item", as the
/// explorer's cubit keeps them.
///
/// The table is rebuilt whenever its folder is left or refreshed in place, so
/// what it should open on has to outlive it, here.
void main() {
  setUpAll(() => registerFallbackValue(SyncTrigger.background));

  const driveId = 'drive-id';
  const rootFolderId = 'root-folder-id';
  const rowsPerPageKey = 'drive_detail_rows_per_page';

  late Database db;
  late _MockDriveRepository driveRepository;
  late MockSyncBloc syncCubit;
  late MockProfileCubit profileCubit;
  late _MockActivityTracker activityTracker;
  late _MockBreadcrumbBuilder breadcrumbBuilder;
  late StreamController<SyncState> syncStates;

  Future<void> insertFolder(String id) => db.into(db.folderEntries).insert(
        FolderEntriesCompanion.insert(
          id: id,
          driveId: driveId,
          parentFolderId: const Value(rootFolderId),
          name: id,
          path: '',
        ),
      );

  Future<void> insertDriveWithFolders(int count) async {
    await db.into(db.drives).insert(
          DrivesCompanion.insert(
            id: driveId,
            name: 'Test Drive',
            ownerAddress: 'owner-address',
            rootFolderId: rootFolderId,
            privacy: DrivePrivacyTag.public,
          ),
        );
    await db.into(db.folderEntries).insert(
          FolderEntriesCompanion.insert(
            id: rootFolderId,
            driveId: driveId,
            name: 'Test Drive',
            path: '',
          ),
        );
    await db.driveDao.insertFolderRevision(
      FolderRevisionsCompanion.insert(
        folderId: rootFolderId,
        driveId: driveId,
        name: 'Test Drive',
        metadataTxId: 'metadata-tx-id',
        action: RevisionAction.create,
      ),
    );
    for (var i = 0; i < count; i++) {
      await insertFolder('folder-$i');
    }
  }

  DriveDetailCubit buildCubit() => DriveDetailCubit(
        driveId: driveId,
        profileCubit: profileCubit,
        driveDao: db.driveDao,
        configService: MockConfigService(),
        activityTracker: activityTracker,
        auth: MockArDriveAuth(),
        breadcrumbBuilder: breadcrumbBuilder,
        syncCubit: syncCubit,
        driveRepository: driveRepository,
      );

  Future<LocalKeyValueStore> store() => LocalKeyValueStore.getInstance();

  DriveDetailLoadSuccess loaded(DriveDetailCubit cubit) =>
      cubit.state as DriveDetailLoadSuccess;

  const settle = Duration(milliseconds: 150);

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // The store keeps its first instance for the whole run.
    await (await store()).remove(rowsPerPageKey);

    db = getTestDb();
    driveRepository = _MockDriveRepository();
    syncCubit = MockSyncBloc();
    profileCubit = MockProfileCubit();
    activityTracker = _MockActivityTracker();
    breadcrumbBuilder = _MockBreadcrumbBuilder();
    syncStates = StreamController<SyncState>.broadcast();

    when(() => driveRepository.watchDrive(driveId: any(named: 'driveId')))
        .thenAnswer((invocation) => db.driveDao
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

  test('a folder not yet visited has no page to return to', () async {
    await insertDriveWithFolders(3);
    final cubit = buildCubit();
    await Future<void>.delayed(settle);

    expect(cubit.pageForFolder(rootFolderId), isNull);
    expect(cubit.scrollOffsetForFolder(rootFolderId), isNull);
    await cubit.close();
  });

  test('returns to the page and scroll a folder was left at', () async {
    await insertDriveWithFolders(3);
    final cubit = buildCubit();
    await Future<void>.delayed(settle);

    cubit.rememberPage(rootFolderId, 2);
    cubit.rememberScrollOffset(rootFolderId, 340);

    expect(cubit.pageForFolder(rootFolderId), 2);
    expect(cubit.scrollOffsetForFolder(rootFolderId), 340);
    expect(cubit.pageForFolder('another-folder'), isNull);

    // A different page is read from its top.
    cubit.rememberPage(rootFolderId, 3);
    expect(cubit.scrollOffsetForFolder(rootFolderId), isNull);
    await cubit.close();
  });

  test('a new page size keeps the same rows in view, and is kept', () async {
    await insertDriveWithFolders(3);
    final cubit = buildCubit();
    await Future<void>.delayed(settle);
    expect(loaded(cubit).rowsPerPage, 25);

    // Rows 76-100.
    cubit.rememberPage(rootFolderId, 3);

    await cubit.setRowsPerPage(50);

    expect(loaded(cubit).rowsPerPage, 50);
    expect(cubit.pageForFolder(rootFolderId), 1, reason: 'rows 51-100');
    expect((await store()).getString(rowsPerPageKey), '50');
    await cubit.close();
  });

  test('opens with the page size kept on this device', () async {
    await (await store()).putString(rowsPerPageKey, '100');
    await insertDriveWithFolders(3);

    final cubit = buildCubit();
    await Future<void>.delayed(settle);

    expect(loaded(cubit).rowsPerPage, 100);
    await cubit.close();
  });

  test('ignores a kept size the table does not offer', () async {
    await (await store()).putString(rowsPerPageKey, '75');
    await insertDriveWithFolders(3);

    final cubit = buildCubit();
    await Future<void>.delayed(settle);

    expect(loaded(cubit).rowsPerPage, 25);
    await cubit.close();
  });

  group('showing one item, such as a search result', () {
    test('asks the table for the item\'s page, once', () async {
      await insertDriveWithFolders(60);
      final cubit = buildCubit();
      await Future<void>.delayed(settle);
      expect(loaded(cubit).revealSelectedItem, isFalse);
      final keyBefore = loaded(cubit).forceRebuildKey;

      unawaited(cubit.openFolder(
        folderId: rootFolderId,
        selectedItemId: 'folder-57',
      ));
      await Future<void>.delayed(settle);

      expect(loaded(cubit).selectedItem?.id, 'folder-57');
      expect(loaded(cubit).revealSelectedItem, isTrue);
      expect(loaded(cubit).forceRebuildKey, isNot(keyBefore),
          reason: 'the folder on screen is the same, so its table is rebuilt');

      // The table reports the page it opened on.
      cubit.rememberPage(rootFolderId, 2);
      await Future<void>.delayed(Duration.zero);
      expect(loaded(cubit).revealSelectedItem, isFalse);

      // The folder changes under the reader, who has moved on.
      cubit.selectDataItem(loaded(cubit).currentFolderContents.first);
      await insertFolder('folder-new');
      await Future<void>.delayed(settle);

      expect(loaded(cubit).revealSelectedItem, isFalse);
      expect(loaded(cubit).selectedItem?.id, isNot('folder-57'),
          reason: 'a later tick does not take the selection back');
      await cubit.close();
    });

    test('waits for an item that has not synced yet', () async {
      await insertDriveWithFolders(3);
      final cubit = buildCubit();
      await Future<void>.delayed(settle);

      unawaited(cubit.openFolder(
        folderId: rootFolderId,
        selectedItemId: 'folder-late',
      ));
      await Future<void>.delayed(settle);
      expect(loaded(cubit).revealSelectedItem, isFalse);

      await insertFolder('folder-late');
      await Future<void>.delayed(settle);

      expect(loaded(cubit).selectedItem?.id, 'folder-late');
      expect(loaded(cubit).revealSelectedItem, isTrue);
      await cubit.close();
    });

    test('selectDataItem can ask for it too', () async {
      await insertDriveWithFolders(30);
      final cubit = buildCubit();
      await Future<void>.delayed(settle);

      await cubit.selectDataItem(
        loaded(cubit).currentFolderContents.last,
        openSelectedPage: true,
      );

      expect(loaded(cubit).revealSelectedItem, isTrue);
      await cubit.close();
    });
  });
}
