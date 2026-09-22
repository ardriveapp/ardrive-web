import 'package:ardrive/blocs/blocs.dart';
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

  Future<void> pressUpload(WidgetTester tester, {DriveDao? driveDao}) async {
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
              BlocProvider<DrivesCubit>.value(value: drivesCubit),
              BlocProvider<DriveDetailCubit>.value(value: detail),
              BlocProvider<SyncCubit>.value(value: sync),
            ],
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => startUpload(context, isFolderUpload: false),
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
}
