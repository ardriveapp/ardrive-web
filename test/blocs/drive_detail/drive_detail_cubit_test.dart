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
  setUpAll(() => registerFallbackValue(SyncTrigger.background));

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

  /// What `SyncCubit` is left in by a sync that ran to the end and succeeded.
  ///
  /// Written once, here, because it is the state the whole "may this panel
  /// report what the sync found?" decision turns on - and because a test that
  /// stubs a bare `SyncIdle` is describing a sync that never ran, whatever the
  /// `startSyncForDrive` stub returned beside it.
  SyncComplete succeededSync() => SyncComplete(
        entitiesSynced: 0,
        sequence: 1,
        completedAt: DateTime(2026, 3, 4),
      );

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

    // The gate reads this alongside syncingDriveId; an empty list is "nothing
    // has finished walking yet", which is true of every state these tests set.
    when(() => syncCubit.completedDriveIds).thenReturn(const []);
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

    /// A drive whose root revision has not arrived *yet* is not a drive that
    /// has never been synced.
    ///
    /// Reading no longer waits for the sync, which is the point - but it means
    /// this branch is now reached mid-walk, where the wait used to keep it
    /// away. Saying "Drive Not Synced" then contradicts the ring still turning
    /// in the top bar, and offers a Sync Now the cubit refuses because a sync
    /// is already running. Reported from the browser: the panel flipped to
    /// Drive Not Synced part way through a sync, with both buttons greyed, and
    /// came right when the sync finished.
    blocTest<DriveDetailCubit, DriveDetailState>(
      'waits rather than claiming "not synced" while that drive is syncing',
      setUp: () async {
        await insertDrive(lastBlockHeight: 0);

        whenListen(syncCubit, syncStates.stream,
            initialState: SyncInProgress(trigger: SyncTrigger.userInitiated));
        when(() => syncCubit.syncingDriveId).thenReturn(driveId);
      },
      build: buildCubit,
      wait: const Duration(milliseconds: 100),
      verify: (cubit) {
        expect(
          cubit.state,
          isNot(isA<DriveDetailLoadUnsynced>()),
          reason: 'the root revision has not landed yet, which is not the same '
              'as never landing',
        );
      },
    );

    /// A wait needs something that can end it.
    ///
    /// The panel waits rather than saying "Drive Not Synced" while a sync is
    /// walking that drive, and the tick that writes the root revision is what
    /// ends the wait. A run that fails, is cancelled, or fails on this drive
    /// in particular writes nothing - so no tick comes, and the panel sat on
    /// "Opening..." until the reader navigated away and back. Before reading
    /// stopped waiting for the sync this could not happen: the check always
    /// ran after the sync had settled.
    blocTest<DriveDetailCubit, DriveDetailState>(
      'a sync that ends without writing the drive does not strand the panel',
      setUp: () async {
        await insertDrive(lastBlockHeight: 0);

        whenListen(syncCubit, syncStates.stream,
            initialState: SyncInProgress(trigger: SyncTrigger.userInitiated));
        when(() => syncCubit.syncingDriveId).thenReturn(driveId);
      },
      build: buildCubit,
      act: (cubit) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(cubit.state, isA<DriveDetailLoadInProgress>(),
            reason: 'precondition: waiting for a revision that may still come');

        // The sync ends having written nothing for this drive.
        when(() => syncCubit.syncingDriveId).thenReturn(null);
        syncStates.add(SyncFailure());
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
      verify: (cubit) {
        expect(
          cubit.state,
          isA<DriveDetailLoadUnsynced>(),
          reason: 'the revision is not coming, so the panel has to say so and '
              'offer a way out rather than spin for ever',
        );
      },
    );

    /// And the claim is still made when nothing is running, because then it is
    /// true and the offer to sync is one the cubit will honour.
    blocTest<DriveDetailCubit, DriveDetailState>(
      'and says it plainly once no sync is running',
      setUp: () async {
        await insertDrive(lastBlockHeight: 0);

        whenListen(syncCubit, syncStates.stream, initialState: SyncIdle());
        when(() => syncCubit.syncingDriveId).thenReturn(null);
      },
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
            trigger: any(named: 'trigger'),
          )).thenAnswer((_) async {
        insertRootFolderRevision();
        // The sync ran - see `SyncCubit.startSyncForDrive`.
        when(() => syncCubit.state).thenReturn(succeededSync());
        return true;
      });

      final emitted = <DriveDetailState>[];
      final subscription = cubit.stream.listen(emitted.add);

      await cubit.syncCurrentDrive();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await subscription.cancel();

      // With "sync drives on login" off this is the primary way a drive gets
      // synced, and somebody pressed it - so the sync history has to say
      // Manual. It ran as `background` to keep the old blocking modal off the
      // panel that was reporting the same sync; that modal is gone, and the
      // summary that replaced it neither scrims nor takes a click. All the
      // trigger still decides is who the record says asked.
      final trigger = verify(() => syncCubit.startSyncForDrive(
            driveId: any(named: 'driveId'),
            deepSync: any(named: 'deepSync'),
            trigger: captureAny(named: 'trigger'),
          )).captured.last;
      expect(trigger, SyncTrigger.userInitiated);

      expect(
        emitted.whereType<DriveDetailLoadUnsynced>(),
        isEmpty,
        reason: 'pressing "Sync now" must not return to "Drive Not Synced" '
            'once the root metadata is readable',
      );
      expect(cubit.state, isA<DriveDetailLoadSuccess>());
    });

    /// `SyncComplete` extends `SyncIdle` precisely so this handler keeps
    /// firing: it gates on `syncState is SyncIdle`, and a sibling state would
    /// leave a drive sitting on "Drive Not Synced" after the sync that fixed
    /// it. Nothing fed a `SyncComplete` through this consumer until now.
    ///
    /// The drive stream is frozen first, so the recovery cannot come from
    /// anywhere else. `watchDrive` is the only thing here that watches the
    /// drives table; pinned to a single emission, the writes below reach the
    /// database without reaching the cubit, and the sync-completion handler is
    /// the only path left that can move it off the unsynced screen.
    test('a finished sync that reports a result still refreshes the drive',
        () async {
      await insertDrive(lastBlockHeight: 0);

      final frozenDrive =
          await driveDao.driveById(driveId: driveId).getSingle();
      when(() => driveRepository.watchDrive(driveId: any(named: 'driveId')))
          .thenAnswer((_) => Stream.value(frozenDrive));

      final cubit = buildCubit();
      addTearDown(cubit.close);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(cubit.state, isA<DriveDetailLoadUnsynced>(),
          reason: 'precondition: the drive starts out unsynced');

      // The sync writes the root revision. Straight into the table rather
      // than through `insertRootFolderRevision`, which also writes the
      // metadata's network transaction - and the folder listing joins that
      // table, so going through the DAO would re-fire the folder stream and
      // repair the state on its own, leaving nothing for this test to prove.
      await db.into(db.folderRevisions).insert(
            FolderRevisionsCompanion.insert(
              folderId: rootFolderId,
              driveId: driveId,
              name: 'Test Drive',
              metadataTxId: 'metadata-tx-id',
              action: RevisionAction.create,
            ),
          );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(cubit.state, isA<DriveDetailLoadUnsynced>(),
          reason: 'precondition: nothing the cubit watches has fired, so only '
              'the sync result can recover this drive');

      syncStates.add(SyncComplete(
        entitiesSynced: 3,
        completedAt: DateTime.now(),
        sequence: 1,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(cubit.state, isA<DriveDetailLoadSuccess>());
    });

    blocTest<DriveDetailCubit, DriveDetailState>(
      'stays unsynced while the root metadata is still missing',
      setUp: () => insertDrive(lastBlockHeight: 0),
      build: buildCubit,
      act: (cubit) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // A result, not a bare idle: a sync that finished having found
        // nothing must not be mistaken for metadata arriving.
        syncStates.add(SyncComplete(
          entitiesSynced: 0,
          completedAt: DateTime.now(),
          sequence: 1,
        ));

        await Future<void>.delayed(const Duration(milliseconds: 200));
      },
      verify: (cubit) {
        expect(cubit.state, isA<DriveDetailLoadUnsynced>());
      },
    );
  });

  group('DriveDetailCubit during a background sync', () {
    const otherDriveId = 'other-drive-id';
    const otherRootFolderId = 'other-root-folder-id';

    /// A second drive, fully readable: the one the user clicks over to.
    Future<void> insertOtherDrive() async {
      await db.into(db.drives).insert(
            DrivesCompanion.insert(
              id: otherDriveId,
              name: 'Other Drive',
              ownerAddress: ownerAddress,
              rootFolderId: otherRootFolderId,
              privacy: DrivePrivacyTag.public,
              lastBlockHeight: const Value(100),
            ),
          );

      await db.into(db.folderEntries).insert(
            FolderEntriesCompanion.insert(
              id: otherRootFolderId,
              driveId: otherDriveId,
              name: 'Other Drive',
              path: '',
            ),
          );

      await driveDao.insertFolderRevision(
        FolderRevisionsCompanion.insert(
          folderId: otherRootFolderId,
          driveId: otherDriveId,
          name: 'Other Drive',
          metadataTxId: 'other-metadata-tx-id',
          action: RevisionAction.create,
        ),
      );
    }

    /// Clicking a drive while the login sync is still running used to produce
    /// nothing at all - no navigation, no spinner, no error, the drive the
    /// user had just left still on screen - for as long as the sync ran, which
    /// on a large wallet is minutes. `openFolder` awaited the sync as its
    /// first statement, and `changeDrive` had already cancelled the folder
    /// subscription and moved the drive id by then, so the screen was showing
    /// something the cubit had already stopped maintaining.
    ///
    /// While a sync scrimmed the whole app the click was impossible. Now that
    /// a background sync leaves the app usable, it is the first thing a tester
    /// does.
    test('a drive clicked during a background sync answers straight away',
        () async {
      await insertDrive(lastBlockHeight: 100);
      await insertRootFolderRevision();
      await insertSubfolder('subfolder-1');
      await insertOtherDrive();

      final cubit = buildCubit();
      addTearDown(cubit.close);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(cubit.state, isA<DriveDetailLoadSuccess>(),
          reason: 'precondition: the first drive is on screen');

      // A sync that is running and never finishes. The point is what the app
      // does *during* it - an all-drives background sync, which is the one
      // that really does cover this drive.
      final syncing = Completer<void>();
      addTearDown(() => syncing.complete());
      when(() => syncCubit.waitCurrentSync()).thenAnswer((_) => syncing.future);
      whenListen(syncCubit, syncStates.stream,
          initialState: SyncInProgress(trigger: SyncTrigger.background));
      when(() => syncCubit.syncingDriveId).thenReturn(null);
      // The run's own scope and what it has finished, read by every surface
      // that tells a drive in the run from one beside it. Null scope is
      // "every drive"; nothing finished yet.
      when(() => syncCubit.syncingDriveIds).thenReturn(null);
      when(() => syncCubit.completedDriveIds).thenReturn(const []);

      unawaited(cubit.changeDrive(otherDriveId));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final state = cubit.state;
      expect(
        state,
        isA<DriveDetailLoadSuccess>(),
        reason: 'the drive opens during the sync rather than after it - the '
            'sync here never finishes, so waiting for it would mean never '
            'opening at all',
      );
      expect((state as DriveDetailLoadSuccess).currentDrive.id, otherDriveId);
      verifyNever(() => syncCubit.waitCurrentSync());
    });

    /// The wait this replaced was there to keep a folder from being read
    /// against a half-written database. It was not needed for that: every
    /// batch commits in its own transaction, so a read mid-sync gets
    /// consistent data - just less of it than the folder will eventually hold,
    /// with the subscription filling the rest in as it lands.
    test('a folder is read during the sync of its own drive, not after it',
        () async {
      await insertDrive(lastBlockHeight: 100);
      await insertRootFolderRevision();
      await insertSubfolder('subfolder-1');
      await insertOtherDrive();

      final cubit = buildCubit();
      addTearDown(cubit.close);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      // A sync of the very drive being opened, which never finishes.
      final syncing = Completer<void>();
      addTearDown(() => syncing.complete());
      when(() => syncCubit.waitCurrentSync()).thenAnswer((_) => syncing.future);
      whenListen(syncCubit, syncStates.stream,
          initialState: SyncInProgress(trigger: SyncTrigger.userInitiated));
      when(() => syncCubit.syncingDriveId).thenReturn(otherDriveId);

      unawaited(cubit.changeDrive(otherDriveId));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final state = cubit.state;
      expect(
        state,
        isA<DriveDetailLoadSuccess>(),
        reason: 'the drive being synced is the one a reader most wants to '
            'watch fill in',
      );
      expect((state as DriveDetailLoadSuccess).currentDrive.id, otherDriveId);
    });

    /// The bug this pair of tests missed for a whole stack: the gate existed
    /// only on the cubit's *first* load. Every drive opened after that goes
    /// through openFolder, which waited for any sync at all - so syncing one
    /// drive pinned every other drive on "loading" for the length of it, and
    /// the panel said "Another drive is syncing" while it happened.
    test('a single-drive sync of another drive does not hold this one shut',
        () async {
      await insertDrive(lastBlockHeight: 100);
      await insertRootFolderRevision();
      await insertSubfolder('subfolder-1');
      await insertOtherDrive();

      final cubit = buildCubit();
      addTearDown(cubit.close);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Running, and deliberately never completed - if the drive only opens
      // when this finishes, it never opens.
      final syncing = Completer<void>();
      addTearDown(() => syncing.complete());
      when(() => syncCubit.waitCurrentSync()).thenAnswer((_) => syncing.future);
      whenListen(syncCubit, syncStates.stream,
          initialState: SyncInProgress(trigger: SyncTrigger.userInitiated));
      // ...for a drive that is not the one being opened.
      when(() => syncCubit.syncingDriveId).thenReturn('a-third-drive-id');

      unawaited(cubit.changeDrive(otherDriveId));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final state = cubit.state;
      expect(
        state,
        isA<DriveDetailLoadSuccess>(),
        reason: 'nothing is writing this drive, so nothing should keep the '
            'reader out of it',
      );
      expect((state as DriveDetailLoadSuccess).currentDrive.id, otherDriveId);
      verifyNever(() => syncCubit.waitCurrentSync());
    });
  });

  /// A tick that was never drawn must not count as drawn.
  ///
  /// The folder subscription skips a redraw while an upload is running, so the
  /// file list does not churn under somebody watching a progress bar. The
  /// change-detection added for sync then has to be careful *where* it records
  /// what is on screen: recorded before that guard, the tick carrying the
  /// newly uploaded file was marked as drawn and then dropped, and any later
  /// tick carrying the same contents was skipped as a no-op. The file never
  /// arrived.
  ///
  /// Reproducing it needs a second tick that carries the *same* folder - which
  /// is what a change to the drive row gives, since the subscription combines
  /// the drive and its contents and re-emits when either moves.
  group('a redraw dropped for an upload', () {
    /// The report that found this: "I uploaded a file, it worked, and I do not
    /// see it in the drive view."
    ///
    /// An upload writes its file while `isUploading` is up, so the tick
    /// carrying it is refused by the guard in the subscription - and nothing
    /// writes that folder again afterwards, so no later tick carries it
    /// either. The upload form then calls `refreshDriveDataTable`, which
    /// re-emitted the state it already had with a new key: the same rows,
    /// rebuilt. The file was uploaded and was not on screen, and nothing short
    /// of leaving the folder and coming back would show it.
    test('is settled by the refresh the upload form calls', () async {
      await insertDrive(lastBlockHeight: 100);
      await insertRootFolderRevision();

      final cubit = buildCubit();
      addTearDown(cubit.close);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(cubit.state, isA<DriveDetailLoadSuccess>(),
          reason: 'precondition: the folder is on screen');

      // The upload runs and writes into the folder being viewed.
      when(() => activityTracker.isUploading).thenReturn(true);
      await insertSubfolder('uploaded-during');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        (cubit.state as DriveDetailLoadSuccess).folderInView.subfolders,
        isEmpty,
        reason: 'precondition: the upload guard refused that redraw',
      );

      // The upload finishes exactly as the form does it, and nothing else
      // touches the database afterwards.
      when(() => activityTracker.isUploading).thenReturn(false);
      cubit.refreshDriveDataTable();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        (cubit.state as DriveDetailLoadSuccess)
            .folderInView
            .subfolders
            .map((f) => f.name),
        contains('uploaded-during'),
        reason: 'the uploaded file has to be on screen when the upload ends, '
            'without the reader navigating away and back',
      );
    });

    test('does not make a later identical tick look like a no-op', () async {
      await insertDrive(lastBlockHeight: 100);
      await insertRootFolderRevision();

      final cubit = buildCubit();
      addTearDown(cubit.close);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(cubit.state, isA<DriveDetailLoadSuccess>(),
          reason: 'precondition: the folder is on screen');

      // An upload runs, and writes a folder into the one on screen. The tick
      // carrying it is dropped rather than drawn.
      when(() => activityTracker.isUploading).thenReturn(true);
      await insertSubfolder('arrived-during-upload');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        (cubit.state as DriveDetailLoadSuccess).folderInView.subfolders,
        isEmpty,
        reason: 'precondition: the upload guard dropped that redraw',
      );

      // The upload ends, and something touches the drive row - a sync
      // advancing its watermark, say. The folder itself is unchanged, so this
      // tick carries exactly the contents the dropped one did.
      when(() => activityTracker.isUploading).thenReturn(false);
      await (db.update(db.drives)..where((d) => d.id.equals(driveId)))
          .write(const DrivesCompanion(lastBlockHeight: Value(200)));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        (cubit.state as DriveDetailLoadSuccess)
            .folderInView
            .subfolders
            .map((f) => f.name),
        contains('arrived-during-upload'),
        reason: 'nothing else is going to change this folder, so a tick '
            'skipped as unchanged is the file never appearing',
      );
    });
  });

  /// What an empty local database means, which is three different things.
  ///
  /// The app used to render all three as one: "Getting Started", two
  /// create-a-drive buttons and an empty sidebar, on EVERY login with an empty
  /// database, for the whole length of the drive-list fetch, on the success
  /// path. `DrivesCubit` reports Drift's immediate empty-table read before
  /// `updateUserDrives` has returned anything, and the wait in
  /// `showEmptyDriveDetail` did not cover that fetch.
  group('DriveDetailCubit and an empty drive list', () {
    /// The cubit as the explorer builds it when there is no drive to show at
    /// all - the state a fresh login lands in before the drive list arrives.
    DriveDetailCubit buildCubitWithNoDrive() => DriveDetailCubit(
          driveId: '',
          profileCubit: profileCubit,
          driveDao: driveDao,
          configService: configService,
          activityTracker: activityTracker,
          auth: auth,
          breadcrumbBuilder: breadcrumbBuilder,
          syncCubit: syncCubit,
          driveRepository: driveRepository,
        );

    /// The drive-list refresh, under the test's control: it finishes when the
    /// test says it has, and not before.
    late Completer<void> driveListRead;

    setUp(() {
      driveListRead = Completer<void>();
      when(() => syncCubit.waitForDriveListRefresh())
          .thenAnswer((_) => driveListRead.future);
      when(() => syncCubit.driveListRefreshFailed).thenReturn(false);
      when(() => syncCubit.syncMetadataOnly()).thenAnswer((_) async {});
    });

    test('does not say the user has no drives while the list is still loading',
        () async {
      final cubit = buildCubitWithNoDrive();
      addTearDown(cubit.close);

      final emitted = <DriveDetailState>[];
      final subscription = cubit.stream.listen(emitted.add);
      addTearDown(subscription.cancel);

      unawaited(cubit.showEmptyDriveDetail());
      await pumpEventQueue(times: 100);

      // Nothing has read the drive list, so nothing may claim it is empty.
      // The explorer stays on the panel that says the drives are loading.
      expect(cubit.state, isA<DriveDetailLoadInProgress>());
      expect(
        emitted.whereType<DriveDetailLoadEmpty>(),
        isEmpty,
        reason: '"Getting Started" is a claim about a list nobody has read',
      );
    });

    test('says the user has no drives once the list has actually been read',
        () async {
      final cubit = buildCubitWithNoDrive();
      addTearDown(cubit.close);

      unawaited(cubit.showEmptyDriveDetail());
      await pumpEventQueue(times: 100);
      expect(cubit.state, isA<DriveDetailLoadInProgress>(),
          reason: 'precondition: the refresh has not finished yet');

      driveListRead.complete();
      await pumpEventQueue(times: 100);

      // The screen is still right for the user it was written for.
      expect(cubit.state, isA<DriveDetailLoadEmpty>());
    });

    test('a refresh that failed is not a user with no drives', () async {
      when(() => syncCubit.driveListRefreshFailed).thenReturn(true);

      final cubit = buildCubitWithNoDrive();
      addTearDown(cubit.close);

      final emitted = <DriveDetailState>[];
      final subscription = cubit.stream.listen(emitted.add);
      addTearDown(subscription.cancel);

      driveListRead.complete();
      await cubit.showEmptyDriveDetail();
      await pumpEventQueue(times: 100);

      expect(cubit.state, isA<DriveDetailDrivesUnavailable>());
      expect(
        emitted.whereType<DriveDetailLoadEmpty>(),
        isEmpty,
        reason: 'we could not find out, so we must not answer',
      );
    });

    test('a retry that succeeds gets the user off the failure screen',
        () async {
      when(() => syncCubit.driveListRefreshFailed).thenReturn(true);

      final cubit = buildCubitWithNoDrive();
      addTearDown(cubit.close);

      driveListRead.complete();
      await cubit.showEmptyDriveDetail();
      await pumpEventQueue(times: 100);
      expect(cubit.state, isA<DriveDetailDrivesUnavailable>(),
          reason: 'precondition: the refresh failed');

      // The retry runs the request that failed, and this time it works.
      when(() => syncCubit.syncMetadataOnly()).thenAnswer((_) async {
        when(() => syncCubit.driveListRefreshFailed).thenReturn(false);
      });

      final emitted = <DriveDetailState>[];
      final subscription = cubit.stream.listen(emitted.add);
      addTearDown(subscription.cancel);

      await cubit.retryLoadingDrives();
      await pumpEventQueue(times: 100);

      verify(() => syncCubit.syncMetadataOnly()).called(1);
      // It says it is working again before it lands anywhere.
      expect(emitted.first, isA<DriveDetailLoadInProgress>());
      expect(cubit.state, isA<DriveDetailLoadEmpty>());
    });

    test('a retry that finds drives does not claim the user has none',
        () async {
      // The bug this pins: showEmptyDriveDetail claimed emptiness from the
      // cubit's own state and never asked whether drives existed. On the
      // login path DrivesCubit had already established that; on the retry
      // path nothing had - so a Try Again that WORKED showed "Getting
      // Started / Create a new drive" to a user who had just been told their
      // drives could not be loaded.
      when(() => syncCubit.driveListRefreshFailed).thenReturn(true);

      final cubit = buildCubitWithNoDrive();
      addTearDown(cubit.close);

      driveListRead.complete();
      await cubit.showEmptyDriveDetail();
      await pumpEventQueue(times: 100);
      expect(cubit.state, isA<DriveDetailDrivesUnavailable>(),
          reason: 'precondition: the refresh failed');

      // This time the retry succeeds AND the drive list turns out to have
      // drives in it.
      when(() => syncCubit.syncMetadataOnly()).thenAnswer((_) async {
        await insertDrive(lastBlockHeight: 0);
        when(() => syncCubit.driveListRefreshFailed).thenReturn(false);
      });

      await cubit.retryLoadingDrives();
      await pumpEventQueue(times: 100);

      expect(cubit.state, isNot(isA<DriveDetailLoadEmpty>()),
          reason: 'told a user with drives that they have none');
    });

    test('a refresh that succeeds anywhere clears the failure screen',
        () async {
      // The top bar has its own Try Again, which calls syncMetadataOnly
      // directly. Without this the body went on saying the drives could not
      // be loaded while the bar above it reported everything was fine.
      when(() => syncCubit.driveListRefreshFailed).thenReturn(true);

      final cubit = buildCubitWithNoDrive();
      addTearDown(cubit.close);

      driveListRead.complete();
      await cubit.showEmptyDriveDetail();
      await pumpEventQueue(times: 100);
      expect(cubit.state, isA<DriveDetailDrivesUnavailable>());

      // The refresh succeeds somewhere else entirely.
      when(() => syncCubit.driveListRefreshFailed).thenReturn(false);
      syncStates.add(SyncIdle());
      await pumpEventQueue(times: 100);

      expect(cubit.state, isNot(isA<DriveDetailDrivesUnavailable>()),
          reason: 'the failure screen outlived the failure');
    });
  });

  /// A sync that ran, finished and found nothing must not be rendered as a
  /// sync that never happened.
  group('DriveDetailCubit after a sync that found nothing', () {
    test('says the sync looked, rather than re-offering the same card',
        () async {
      await insertDrive(lastBlockHeight: 0);

      final cubit = buildCubit();
      addTearDown(cubit.close);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      final before = cubit.state;
      expect(before, isA<DriveDetailLoadUnsynced>(),
          reason: 'precondition: the drive starts out unsynced');
      expect((before as DriveDetailLoadUnsynced).syncFoundNothing, isFalse,
          reason: 'precondition: nothing has been synced yet');

      // The sync runs to the end and writes no root revision - the drive's
      // metadata simply is not out there yet.
      when(() => syncCubit.startSyncForDrive(
            driveId: any(named: 'driveId'),
            deepSync: any(named: 'deepSync'),
            trigger: any(named: 'trigger'),
          )).thenAnswer((_) async => true);
      // What a sync that ran to the end actually leaves behind. Only this
      // state entitles the panel to report what the sync found.
      when(() => syncCubit.state).thenReturn(succeededSync());

      await cubit.syncCurrentDrive();
      await pumpEventQueue(times: 100);

      final after = cubit.state;
      expect(after, isA<DriveDetailLoadUnsynced>());
      expect(
        (after as DriveDetailLoadUnsynced).syncFoundNothing,
        isTrue,
        reason: 'the card the user pressed Sync Now on must not come back '
            'word for word, as though the press did nothing',
      );
    });

    test('nor about an all-drives sync that never started', () async {
      // The sibling of the test below, and the one that survived the first
      // fix: `startSync` used to return void, so this path guessed from
      // `SyncInProgress` beforehand - which is blind to a sync that declines
      // for a hidden tab, an uninterruptible activity, or a cancellation. Each
      // of those reads afterwards as a drive as empty as it was.
      await insertDrive(lastBlockHeight: 0);

      final cubit = buildCubit();
      addTearDown(cubit.close);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(cubit.state, isA<DriveDetailLoadUnsynced>(),
          reason: 'precondition: the drive starts out unsynced');

      // Declined for a reason the state before the call cannot show.
      when(() => syncCubit.startSync(
            deepSync: any(named: 'deepSync'),
            trigger: any(named: 'trigger'),
            skipTabVisibilityCheck: any(named: 'skipTabVisibilityCheck'),
            onlyDriveIds: any(named: 'onlyDriveIds'),
          )).thenAnswer((_) async => false);
      when(() => syncCubit.state).thenReturn(SyncIdle());

      await cubit.syncAllAndRefreshCurrentDrive();
      await pumpEventQueue(times: 100);

      final after = cubit.state;
      expect(after, isA<DriveDetailLoadUnsynced>());
      expect(
        (after as DriveDetailLoadUnsynced).syncFoundNothing,
        isFalse,
        reason: 'nothing ran, so nothing may be reported about what it found',
      );
    });

    test('and says nothing at all about a sync that never started', () async {
      // One sync at a time, no queue: `startSyncForDrive` refuses outright
      // while one is running and returns having started nothing. Reading the
      // drive afterwards and reporting what it found turns that refusal into
      // "the sync looked and found nothing" - a sentence about a sync that
      // never happened.
      await insertDrive(lastBlockHeight: 0);

      final cubit = buildCubit();
      addTearDown(cubit.close);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(cubit.state, isA<DriveDetailLoadUnsynced>(),
          reason: 'precondition: the drive starts out unsynced');

      // The refusal, exactly as the cubit reports it.
      when(() => syncCubit.startSyncForDrive(
            driveId: any(named: 'driveId'),
            deepSync: any(named: 'deepSync'),
            trigger: any(named: 'trigger'),
          )).thenAnswer((_) async => false);
      when(() => syncCubit.state).thenReturn(SyncIdle());

      final emitted = <DriveDetailState>[];
      final subscription = cubit.stream.listen(emitted.add);
      addTearDown(subscription.cancel);

      await cubit.syncCurrentDrive();
      await pumpEventQueue(times: 100);

      final after = cubit.state;
      expect(after, isA<DriveDetailLoadUnsynced>());
      expect(
        (after as DriveDetailLoadUnsynced).syncFoundNothing,
        isFalse,
        reason: 'nothing ran, so nothing may be reported about what it found',
      );
      expect(
        emitted.whereType<DriveDetailLoadUnsynced>().where(
              (state) => state.syncFoundNothing,
            ),
        isEmpty,
        reason: 'not even in passing',
      );
    });
  });

  /// A sync that did not succeed has not "found" anything, and the user is
  /// entitled to know the read failed rather than be told their drive has not
  /// turned up on Arweave yet.
  group('DriveDetailCubit after a sync that did not succeed', () {
    /// Every terminal state a sync can end in that is not a success, and what
    /// each one is.
    ///
    /// A list rather than three tests, because the point is the shape of the
    /// rule: the guard used to name `SyncCancelled` and `SyncFailure`, and
    /// `SyncCompleteWithErrors` - added later - fell straight through it into
    /// "the sync finished, but nothing for this drive has appeared on Arweave
    /// yet". `_LaterState` stands for the state somebody adds next.
    final endings = <String, SyncState>{
      'a sync that failed on some drives': SyncCompleteWithErrors(
        failedDrives: 1,
        totalDrives: 1,
        failedDriveIds: const [driveId],
        errorMessages: const {driveId: 'gateway said no'},
      ),
      'a sync that was cancelled': SyncCancelled(
        drivesCompleted: 0,
        totalDrives: 1,
        cancelledAt: DateTime(2026, 3, 4),
      ),
      'a sync that failed outright': SyncFailure(error: 'boom'),
      'a state that did not exist when the guard was written': _LaterState(),
    };

    endings.forEach((description, syncState) {
      test('$description is not reported as a look that found nothing',
          () async {
        await insertDrive(lastBlockHeight: 0);

        final cubit = buildCubit();
        addTearDown(cubit.close);

        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(cubit.state, isA<DriveDetailLoadUnsynced>(),
            reason: 'precondition: the drive starts out unsynced');

        // A sync did start - this is not the refusal path - and it ended here.
        when(() => syncCubit.startSyncForDrive(
              driveId: any(named: 'driveId'),
              deepSync: any(named: 'deepSync'),
              trigger: any(named: 'trigger'),
            )).thenAnswer((_) async {
          when(() => syncCubit.state).thenReturn(syncState);
          return true;
        });

        final emitted = <DriveDetailState>[];
        final subscription = cubit.stream.listen(emitted.add);
        addTearDown(subscription.cancel);

        await cubit.syncCurrentDrive();
        await pumpEventQueue(times: 100);

        expect(
          emitted.whereType<DriveDetailLoadUnsynced>().where(
                (state) => state.syncFoundNothing,
              ),
          isEmpty,
          reason: 'the network read did not succeed, so "the sync finished, '
              'but nothing for this drive has appeared on Arweave yet" is a '
              'reassuring explanation for something that did not happen',
        );
      });

      test('$description leaves a screen the user can act from', () async {
        // The other half of the same bug: a guard that returns without
        // emitting leaves the explorer on the loading state this method put
        // up - "Opening Drive X", a sweeping bar, no elapsed time, forever.
        // Neither the following SyncIdle nor a later Resync rescues it.
        await insertDrive(lastBlockHeight: 0);

        final cubit = buildCubit();
        addTearDown(cubit.close);

        await Future<void>.delayed(const Duration(milliseconds: 100));

        when(() => syncCubit.startSyncForDrive(
              driveId: any(named: 'driveId'),
              deepSync: any(named: 'deepSync'),
              trigger: any(named: 'trigger'),
            )).thenAnswer((_) async {
          when(() => syncCubit.state).thenReturn(syncState);
          return true;
        });

        await cubit.syncCurrentDrive();
        await pumpEventQueue(times: 100);

        expect(
          cubit.state,
          isNot(isA<DriveDetailLoadInProgress>()),
          reason: 'nothing else emits after this, so a loading state left up '
              'here is a screen with no way out of it',
        );
        expect(cubit.state, isA<DriveDetailLoadUnsynced>());
      });
    });

    test('nor after an all-drives sync that failed on some drives', () async {
      // `syncAllAndRefreshCurrentDrive` had the identical hole.
      await insertDrive(lastBlockHeight: 0);

      final cubit = buildCubit();
      addTearDown(cubit.close);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(cubit.state, isA<DriveDetailLoadUnsynced>(),
          reason: 'precondition: the drive starts out unsynced');

      when(() => syncCubit.startSync(
            deepSync: any(named: 'deepSync'),
            trigger: any(named: 'trigger'),
            skipTabVisibilityCheck: any(named: 'skipTabVisibilityCheck'),
            onlyDriveIds: any(named: 'onlyDriveIds'),
          )).thenAnswer((_) async {
        when(() => syncCubit.state).thenReturn(SyncCompleteWithErrors(
          failedDrives: 1,
          totalDrives: 3,
          failedDriveIds: const [driveId],
          errorMessages: const {driveId: 'gateway said no'},
        ));
        return true;
      });

      final emitted = <DriveDetailState>[];
      final subscription = cubit.stream.listen(emitted.add);
      addTearDown(subscription.cancel);

      await cubit.syncAllAndRefreshCurrentDrive();
      await pumpEventQueue(times: 100);

      expect(
        emitted.whereType<DriveDetailLoadUnsynced>().where(
              (state) => state.syncFoundNothing,
            ),
        isEmpty,
        reason: 'a sync that failed on this drive may not report what it '
            'found here',
      );
      expect(cubit.state, isA<DriveDetailLoadUnsynced>());
      expect(cubit.state, isNot(isA<DriveDetailLoadInProgress>()));
    });
  });
}

/// The state somebody adds after this guard was written.
///
/// It exists so the rule is tested as a rule. Every sync state inherits
/// `isSuccessfulCompletion => false` and has to say otherwise to be treated as
/// a success, so a state nobody has thought of yet cannot become a sentence
/// about what a sync found.
class _LaterState extends SyncState {}
