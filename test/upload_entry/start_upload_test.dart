import 'package:ardrive/blocs/blocs.dart';
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

import '../test_utils/mocks.dart';

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

  void syncState({String? syncingDriveId}) {
    whenListen(
      sync,
      const Stream<SyncState>.empty(),
      initialState: syncingDriveId == null ? SyncIdle() : SyncInProgress(),
    );
    when(() => sync.syncingDriveId).thenReturn(syncingDriveId);
    when(() => sync.syncingDriveIds)
        .thenReturn(syncingDriveId == null ? null : {syncingDriveId});
  }

  Future<void> pressUpload(WidgetTester tester) async {
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
}
