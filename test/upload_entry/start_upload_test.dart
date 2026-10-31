import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:drift/drift.dart' show Selectable;
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/upload_entry/domain/upload_request.dart';
import 'package:ardrive/upload_entry/presentation/start_upload.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../test_utils/utils.dart';

class _MockActivityTracker extends Mock implements ActivityTracker {}

class _MockFolderSelectable extends Mock implements Selectable<FolderEntry> {}

class _MockFileSelectable extends Mock implements Selectable<FileEntry> {}

final _work = Drive(
  id: 'work',
  rootFolderId: 'root-work',
  ownerAddress: 'owner',
  name: 'Work',
  privacy: 'private',
  isHidden: false,
  dateCreated: DateTime(2026),
  lastUpdated: DateTime(2026),
);

final _photos = Drive(
  id: 'photos',
  rootFolderId: 'root-photos',
  ownerAddress: 'owner',
  name: 'Photos',
  privacy: 'private',
  isHidden: false,
  dateCreated: DateTime(2026),
  lastUpdated: DateTime(2026),
);

/// Upload pressed on the drives list, into its only drive.
///
/// The drive opens and an upload waits for it - but only for the second or
/// two opening takes. The explorer waits out a sync on the drive before it
/// reports anything, which can be minutes, and an upload dialog must not turn
/// up at the end of that.
void main() {
  late MockDrivesCubit drivesCubit;
  late MockDriveDetailCubit detail;
  late MockSyncBloc sync;
  late AppRouterDelegate router;

  setUp(() {
    drivesCubit = MockDrivesCubit();
    detail = MockDriveDetailCubit();
    sync = MockSyncBloc();
    router = AppRouterDelegate()..showingDrivesList = true;

    whenListen(
      drivesCubit,
      const Stream<DrivesState>.empty(),
      initialState: DrivesLoadSuccess(
        selectedDriveId: null,
        userDrives: [_photos],
        sharedDrives: const [],
        drivesWithAlerts: const [],
        canCreateNewDrive: true,
      ),
    );
    whenListen(
      detail,
      const Stream<DriveDetailState>.empty(),
      initialState: DriveDetailLoadInProgress(),
    );
    when(() => sync.completedDriveIds).thenReturn(const []);
  });

  void syncState({String? syncingDriveId, SyncState? state}) {
    whenListen(
      sync,
      const Stream<SyncState>.empty(),
      initialState:
          state ?? (syncingDriveId == null ? SyncIdle() : SyncInProgress()),
    );
    when(() => sync.syncingDriveId).thenReturn(syncingDriveId);
    when(() => sync.syncingDriveIds)
        .thenReturn(syncingDriveId == null ? null : {syncingDriveId});
  }

  Future<void> pressUpload(
    WidgetTester tester, {
    DriveDao? driveDao,
    UploadPrompt? prompt,
    bool webPagesOn = true,
  }) async {
    final config = MockConfigService();
    when(() => config.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      enableDriveStatePublishing: webPagesOn,
    ));
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: MultiProvider(
            providers: [
              if (driveDao != null) ...[
                RepositoryProvider<DriveDao>.value(value: driveDao),
                // `showArDriveDialog` pauses the activity tracker while a
                // dialog is up, so the chooser needs one.
                ListenableProvider<ActivityTracker>.value(
                  value: _MockActivityTracker(),
                ),
              ],
              ListenableProvider<AppRouterDelegate>.value(value: router),
              RepositoryProvider<ConfigService>.value(value: config),
              BlocProvider<DrivesCubit>.value(value: drivesCubit),
              BlocProvider<DriveDetailCubit>.value(value: detail),
              BlocProvider<SyncCubit>.value(value: sync),
            ],
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => startUpload(
                    context,
                    isFolderUpload: false,
                    prompt: prompt,
                  ),
                  child: const Text('Upload'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Upload'));
    await tester.pump();
  }

  /// Two drives, so Upload asks which one before it opens anything.
  Future<void> pressUploadWithTwoDrives(WidgetTester tester) async {
    whenListen(
      drivesCubit,
      const Stream<DrivesState>.empty(),
      initialState: DrivesLoadSuccess(
        selectedDriveId: null,
        userDrives: [_photos, _work],
        sharedDrives: const [],
        drivesWithAlerts: const [],
        canCreateNewDrive: true,
      ),
    );

    await pressUpload(tester, driveDao: getTestDb().driveDao);
    await tester.pumpAndSettle();
  }

  testWidgets('opens the drive with the upload waiting for it', (tester) async {
    syncState();

    await pressUpload(tester);

    verify(() => drivesCubit.selectDrive('photos')).called(1);
    expect(
      router.pendingUpload,
      const UploadRequest(driveId: 'photos', isFolderUpload: false),
    );

    // Nothing here opens the drive, so the wait runs out.
    await tester.pump(AppRouterDelegate.uploadWaitLimit);
    expect(router.pendingUpload, isNull);
  });

  testWidgets('says so, and waits for nothing, while a sync reads the drive',
      (tester) async {
    syncState(syncingDriveId: 'photos');

    await pressUpload(tester);

    expect(
      find.text('This drive is syncing. Try again once it finishes.'),
      findsOneWidget,
    );
    expect(router.pendingUpload, isNull);
    verify(() => drivesCubit.selectDrive('photos')).called(1);
  });

  /// A refresh of the drive list does not hold the drive: it opens in the
  /// usual second or two. Saying it was syncing, and dropping the upload,
  /// would be wrong on both counts. At login it can run for many seconds.
  testWidgets('waits for the drive through a refresh of the drive list',
      (tester) async {
    syncState(state: SyncLoadingDrives());

    await pressUpload(tester);

    expect(
      find.text('This drive is syncing. Try again once it finishes.'),
      findsNothing,
    );
    expect(
      router.pendingUpload,
      const UploadRequest(driveId: 'photos', isFolderUpload: false),
    );

    await tester.pump(AppRouterDelegate.uploadWaitLimit);
  });

  /// The drive chooser hands its answer back after its own dialog has closed.
  /// Everything that callback needs is read while the press is still on
  /// screen: the shell that provided the context can be gone by the time a
  /// drive is picked, and a lookup on an unmounted context throws.
  testWidgets('choosing a drive opens it with the upload waiting',
      (tester) async {
    syncState();

    await pressUploadWithTwoDrives(tester);

    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);

    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    verify(() => drivesCubit.selectDrive('work')).called(1);
    expect(
      router.pendingUpload,
      const UploadRequest(driveId: 'work', isFolderUpload: false),
    );

    await tester.pump(AppRouterDelegate.uploadWaitLimit);
  });

  /// Web pages and Names hold no folder, and their explorer cubit stays
  /// loading. Upload there used to queue an upload for an explorer that
  /// never opened, and did nothing. It asks where instead, opening on the
  /// last drive and folder the reader had open.
  group('on Web pages', () {
    late MockDriveDao driveDao;
    final uploads = <({String driveId, String folderId, Drive? drive})>[];

    Future<void> recordUpload(
      BuildContext context, {
      required String driveId,
      required String parentFolderId,
      required bool isFolderUpload,
      Drive? drive,
    }) async =>
        uploads.add((driveId: driveId, folderId: parentFolderId, drive: drive));

    FolderEntry entry(Drive drive, String id, String name, {String? parent}) =>
        FolderEntry(
          id: id,
          driveId: drive.id,
          name: name,
          parentFolderId: parent,
          path: '',
          dateCreated: DateTime(2026),
          lastUpdated: DateTime(2026),
          isGhost: false,
          isHidden: false,
        );

    void folder(Drive drive, FolderEntry entry, List<FolderEntry> subfolders) {
      final one = _MockFolderSelectable();
      when(() => one.getSingleOrNull()).thenAnswer((_) async => entry);
      when(() => driveDao.folderById(folderId: entry.id)).thenReturn(one);
      final many = _MockFolderSelectable();
      when(() => many.get()).thenAnswer((_) async => subfolders);
      when(() => driveDao.foldersInFolder(
          driveId: drive.id, parentFolderId: entry.id)).thenReturn(many);
      final files = _MockFileSelectable();
      when(() => files.get()).thenAnswer((_) async => const []);
      when(() => driveDao.filesInFolder(
          driveId: drive.id, parentFolderId: entry.id)).thenReturn(files);
    }

    setUp(() {
      uploads.clear();
      syncState();
      driveDao = MockDriveDao();
      final photosRoot = entry(_photos, _photos.rootFolderId, _photos.name);
      final holidays =
          entry(_photos, 'holidays', 'Holidays', parent: photosRoot.id);
      folder(_photos, photosRoot, [holidays]);
      folder(_photos, holidays, const []);
      folder(_work, entry(_work, _work.rootFolderId, _work.name), const []);
      whenListen(
        drivesCubit,
        const Stream<DrivesState>.empty(),
        initialState: DrivesLoadSuccess(
          selectedDriveId: _photos.id,
          userDrives: [_photos, _work],
          sharedDrives: const [],
          drivesWithAlerts: const [],
          canCreateNewDrive: true,
        ),
      );
      router = AppRouterDelegate()
        ..showingWebPages = true
        ..driveId = _photos.id
        ..driveFolderId = 'holidays';
    });

    testWidgets('asks where, on the last folder open', (tester) async {
      await pressUpload(tester, driveDao: driveDao, prompt: recordUpload);
      await tester.pumpAndSettle();

      expect(find.text('Upload file(s)'), findsOneWidget);
      expect(find.text('Holidays'), findsOneWidget);
      expect(find.text('This folder is empty'), findsOneWidget);
      expect(find.text('Upload here'), findsOneWidget);
      expect(router.pendingUpload, isNull,
          reason: 'nothing waits for an explorer that will not open');
      verifyNever(() => drivesCubit.selectDrive(any()));

      // Back to the drive's root, where Holidays is a folder to open.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Photos'), findsWidgets);
      expect(find.text('Holidays'), findsOneWidget);
    });

    testWidgets('Upload here uploads into the folder in view', (tester) async {
      await pressUpload(tester, driveDao: driveDao, prompt: recordUpload);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Upload here'));
      await tester.pumpAndSettle();

      expect(uploads, [
        (driveId: _photos.id, folderId: 'holidays', drive: _photos),
      ]);
      expect(find.text('Upload here'), findsNothing, reason: 'it closed');
    });

    testWidgets('and into another drive, when that is where the reader went',
        (tester) async {
      await pressUpload(tester, driveDao: driveDao, prompt: recordUpload);
      await tester.pumpAndSettle();

      // Up to the drives, then into Work.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload here'));
      await tester.pumpAndSettle();

      expect(uploads, [
        (driveId: _work.id, folderId: _work.rootFolderId, drive: _work),
      ]);
    });

    testWidgets('with Web pages off, Upload does what it does on Your drives',
        (tester) async {
      // The drives list stands in for the page, so the drive opens with the
      // upload waiting, and no picker asks where.
      await pressUpload(
        tester,
        driveDao: driveDao,
        prompt: recordUpload,
        webPagesOn: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Upload here'), findsNothing);
      expect(find.text('Upload to which drive?'), findsOneWidget);
    });
  });
}
