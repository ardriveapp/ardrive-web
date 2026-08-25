import 'dart:async';

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drive_detail/utils/breadcrumb_builder.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/arfs/repository/drive_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_utils/utils.dart';

class MockDriveRepository extends Mock implements DriveRepository {}

class MockActivityTracker extends Mock implements ActivityTracker {}

class MockBreadcrumbBuilder extends Mock implements BreadcrumbBuilder {}

/// These tests run against a real in-memory database and a real [DriveDao], and
/// mock only what sits outside the drive explorer. That is deliberate: every
/// bug this suite exists to catch lived in how the cubit reacts to what the
/// database streams actually emit - a folder row that is absent, a revision
/// that is missing, a load that resolves after the user moved on. A DriveDao
/// stubbed with canned answers reproduces none of that.
void main() {
  late Database db;
  late DriveDao driveDao;
  late MockDriveRepository driveRepository;
  late MockSyncBloc syncCubit;
  late MockProfileCubit profileCubit;
  late MockActivityTracker activityTracker;
  late MockBreadcrumbBuilder breadcrumbBuilder;
  late MockArDriveAuth auth;
  late MockConfigService configService;
  late StreamController<SyncState> syncStates;

  const driveId = 'drive-id';
  const rootFolderId = 'root-folder-id';
  const ownerAddress = 'owner-address';

  /// Writes the drive and its root folder the way a discovered drive lands:
  /// the drive row plus the root folder placeholder, and no revision, because
  /// the root folder's metadata has never been read.
  Future<void> insertDrive({int? lastBlockHeight}) async {
    await db.into(db.drives).insert(
          DrivesCompanion.insert(
            id: driveId,
            name: 'Test Drive',
            ownerAddress: ownerAddress,
            rootFolderId: rootFolderId,
            privacy: DrivePrivacyTag.public,
            lastBlockHeight: Value(lastBlockHeight),
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
  }

  /// The signal that the root folder's metadata has actually been read.
  Future<void> insertRootFolderRevision() async {
    await driveDao.insertFolderRevision(
      FolderRevisionsCompanion.insert(
        folderId: rootFolderId,
        driveId: driveId,
        name: 'Test Drive',
        metadataTxId: 'metadata-tx-id',
        action: RevisionAction.create,
      ),
    );
  }

  /// Contents, via a subfolder rather than a file: `driveIsEmpty` counts both,
  /// and the folder listing is a plain query, where the file listing joins
  /// revisions and network transactions that say nothing about this behaviour.
  Future<void> insertSubfolder(String folderId) async {
    await db.into(db.folderEntries).insert(
          FolderEntriesCompanion.insert(
            id: folderId,
            driveId: driveId,
            parentFolderId: const Value(rootFolderId),
            name: folderId,
            path: '',
          ),
        );
  }

  DriveDetailCubit buildCubit() => DriveDetailCubit(
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

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    db = getTestDb();
    driveDao = db.driveDao;

    driveRepository = MockDriveRepository();
    syncCubit = MockSyncBloc();
    profileCubit = MockProfileCubit();
    activityTracker = MockActivityTracker();
    breadcrumbBuilder = MockBreadcrumbBuilder();
    auth = MockArDriveAuth();
    configService = MockConfigService();
    syncStates = StreamController<SyncState>.broadcast();

    when(() => driveRepository.watchDrive(driveId: any(named: 'driveId')))
        .thenAnswer((invocation) => driveDao
            .driveById(
              driveId: invocation.namedArguments[#driveId] as String,
            )
            .watchSingleOrNull());

    when(() => syncCubit.waitCurrentSync()).thenAnswer((_) async {});
    whenListen(syncCubit, syncStates.stream, initialState: SyncIdle());

    // The cubit reads the profile through `stream.startWith(...)`, so an empty
    // stream is enough: it renders as a logged-out viewer without write
    // permissions, which none of these assertions depend on.
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

  group('DriveDetailCubit empty vs unsynced', () {
    /// The regression that matters most: an unsynced drive rendering as an
    /// empty one tells the user their files are gone.
    blocTest<DriveDetailCubit, DriveDetailState>(
      'says "not synced" for a drive whose root metadata never arrived',
      setUp: () => insertDrive(lastBlockHeight: 0),
      build: buildCubit,
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(cubit.state, isA<DriveDetailLoadUnsynced>());
      },
    );

    /// The mirror case, and the reason `lastBlockHeight` cannot be the signal:
    /// a drive created in-app writes a root revision but never advances its
    /// watermark, so gating on the watermark would tell someone who just made
    /// a drive that it needs syncing before they can use it.
    blocTest<DriveDetailCubit, DriveDetailState>(
      'renders a locally created empty drive as empty, not unsynced',
      setUp: () async {
        await insertDrive(lastBlockHeight: 0);
        await insertRootFolderRevision();
      },
      build: buildCubit,
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        final state = cubit.state;
        expect(state, isA<DriveDetailLoadSuccess>());
        expect((state as DriveDetailLoadSuccess).driveIsEmpty, isTrue);
      },
    );

    blocTest<DriveDetailCubit, DriveDetailState>(
      'renders a drive that has contents',
      setUp: () async {
        await insertDrive(lastBlockHeight: 0);
        await insertRootFolderRevision();
        await insertSubfolder('subfolder-1');
      },
      build: buildCubit,
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        final state = cubit.state;
        expect(state, isA<DriveDetailLoadSuccess>());
        expect((state as DriveDetailLoadSuccess).driveIsEmpty, isFalse);
      },
    );

    /// A drive that synced normally is opened on its watermark alone, without
    /// depending on a revision row being present.
    blocTest<DriveDetailCubit, DriveDetailState>(
      'opens a drive whose watermark has advanced',
      setUp: () async {
        await insertDrive(lastBlockHeight: 100);
        await insertRootFolderRevision();
      },
      build: buildCubit,
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(cubit.state, isA<DriveDetailLoadSuccess>());
      },
    );
  });

  group('DriveDetailCubit recovery from unsynced', () {
    /// An end-to-end guard: metadata arriving must clear the unsynced screen
    /// even though the watermark never moves. It does not pin any particular
    /// path - recovery here comes from the folder stream re-firing, so this
    /// still passes if the sync-completion handler regresses. The
    /// syncCurrentDrive test below is the one that holds that behaviour.
    blocTest<DriveDetailCubit, DriveDetailState>(
      'recovers when the root revision arrives, even with a 0 watermark',
      setUp: () => insertDrive(lastBlockHeight: 0),
      build: buildCubit,
      act: (cubit) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(cubit.state, isA<DriveDetailLoadUnsynced>(),
            reason: 'precondition: the drive starts out unsynced');

        // Metadata lands, but the watermark never moves.
        await insertRootFolderRevision();
        syncStates.add(SyncIdle());

        await Future<void>.delayed(const Duration(milliseconds: 200));
      },
      verify: (cubit) {
        expect(cubit.state, isA<DriveDetailLoadSuccess>());
      },
    );

    /// [DriveDetailCubit.syncCurrentDrive] emits directly rather than through
    /// the folder stream, so it is where an entry/exit mismatch actually
    /// traps the user: pressing "Sync now" on a drive whose metadata has
    /// arrived, but whose watermark never moved, re-emitted the same unsynced
    /// state - the button led back to the screen that offered it.
    /// Asserted on the emissions rather than the final state, and that is the
    /// whole point. The folder subscription is still live here, and writing the
    /// revision touches tables it watches, so the stream re-fires and repairs
    /// the state a moment later no matter what this path emitted. Checking
    /// where the cubit ends up therefore passes even when the button is
    /// broken; only the sequence shows the user being bounced back to the
    /// screen they just acted on.
    test(
        'syncCurrentDrive() does not land back on the unsynced screen when '
        'metadata arrived with a 0 watermark', () async {
      await insertDrive(lastBlockHeight: 0);

      final cubit = buildCubit();
      addTearDown(cubit.close);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(cubit.state, isA<DriveDetailLoadUnsynced>(),
          reason: 'precondition: the drive starts out unsynced');

      // The sync writes the root revision but never advances the watermark.
      when(() => syncCubit.startSyncForDrive(
            driveId: any(named: 'driveId'),
            deepSync: any(named: 'deepSync'),
          )).thenAnswer((_) async => insertRootFolderRevision());

      final emitted = <DriveDetailState>[];
      final subscription = cubit.stream.listen(emitted.add);

      await cubit.syncCurrentDrive();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await subscription.cancel();

      expect(
        emitted.whereType<DriveDetailLoadUnsynced>(),
        isEmpty,
        reason: 'pressing "Sync now" must not return to "Drive Not Synced" '
            'once the root metadata is readable',
      );
      expect(cubit.state, isA<DriveDetailLoadSuccess>());
    });

    blocTest<DriveDetailCubit, DriveDetailState>(
      'stays unsynced while the root metadata is still missing',
      setUp: () => insertDrive(lastBlockHeight: 0),
      build: buildCubit,
      act: (cubit) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));

        syncStates.add(SyncIdle());

        await Future<void>.delayed(const Duration(milliseconds: 200));
      },
      verify: (cubit) {
        expect(cubit.state, isA<DriveDetailLoadUnsynced>());
      },
    );
  });
}
