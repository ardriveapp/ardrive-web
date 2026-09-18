import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/fake_user.dart';
import '../test_utils/utils.dart';

/// A drive's details, for a drive this device has never synced.
///
/// The panel used to spin forever for one, and had no way to be closed where
/// the explorer showed it. It now says what it knows - the drive's id and
/// dates - and where its size and contents would be, why they are not known,
/// with the drive's own way to sync.
void main() {
  const driveId = 'drive';
  const rootFolderId = 'root';

  late Database db;
  late Drive drive;
  late MockSyncBloc sync;
  late MockArDriveAuth auth;
  late int closed;
  late int synced;

  setUp(() async {
    db = getTestDb();
    sync = MockSyncBloc();
    auth = MockArDriveAuth();
    closed = 0;
    synced = 0;

    whenListen(
      sync,
      const Stream<SyncState>.empty(),
      initialState: SyncIdle(),
    );
    when(() => auth.currentUser).thenReturn(fakeUserJson);

    // What reading the drive list leaves behind: the drive and a placeholder
    // root folder, and no revisions.
    await db.batch((batch) {
      batch.insert(
        db.drives,
        DrivesCompanion.insert(
          id: driveId,
          rootFolderId: rootFolderId,
          ownerAddress: fakeUserJson.walletAddress,
          name: 'Photos',
          privacy: DrivePrivacyTag.public,
        ),
      );
      batch.insert(
        db.folderEntries,
        FolderEntriesCompanion.insert(
          id: rootFolderId,
          driveId: driveId,
          name: 'Photos',
          isHidden: const Value(false),
          path: '',
        ),
      );
    });
    drive = await db.driveDao.driveById(driveId: driveId).getSingle();
  });

  tearDown(() => db.close());

  Future<void> pumpPanel(WidgetTester tester, {bool withSync = true}) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // What `MediaQuery` reports, which is what picks the panel's desktop
    // layout - the one with a toolbar. The surface size alone leaves it at
    // the test default, a tablet.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final arweave = MockArweaveService();
    when(
      () => arweave.getAllSnapshotsOfDrive(
        any(),
        any(),
        ownerAddress: any(named: 'ownerAddress'),
      ),
    ).thenAnswer((_) => const Stream.empty());

    // On the real clock: the panel's cubits read the database, and that work
    // never finishes on the test's fake one - nor does closing it afterwards.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<DriveDao>.value(value: db.driveDao),
            RepositoryProvider<ArweaveService>.value(value: arweave),
            RepositoryProvider<LicenseService>.value(
              value: MockLicenseService(),
            ),
            RepositoryProvider<ConfigService>.value(value: MockConfigService()),
            RepositoryProvider<ArDriveAuth>.value(value: auth),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ProfileCubit>.value(value: MockProfileCubit()),
              BlocProvider<SyncCubit>.value(value: sync),
            ],
            child: Portal(
              child: ArDriveTheme(
                themeData: lightTheme(),
                child: MaterialApp(
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: const [Locale('en', '')],
                  home: Scaffold(
                    body: SizedBox(
                      width: 420,
                      child: DetailsPanel(
                        item: DriveDataTableItemMapper.fromDrive(
                          drive,
                          (_) {},
                          0,
                          true,
                        ),
                        currentDrive: drive,
                        canNavigateThroughImages: false,
                        onClose: () => closed++,
                        onSync: withSync ? () => synced++ : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // The drive's details come out of the database.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  /// Takes the panel down on the real clock. Left to the framework, it goes
  /// down on the fake one, where closing its database streams never finishes -
  /// before any tear-down could step in.
  Future<void> takeDown(WidgetTester tester) => tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

  Finder toolbarAction(String tooltip) => find.byWidgetPredicate(
        (w) => w is ArDriveIconButton && w.tooltip == tooltip,
      );

  testWidgets('says what it knows, not a spinner', (tester) async {
    await pumpPanel(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Never synced'), findsOneWidget);
    expect(
      find.text(
        'This drive has not been synced on this device, so its size and '
        'contents are not known yet.',
      ),
      findsOneWidget,
    );

    await takeDown(tester);
  });

  /// Offered, never done for the reader: opening a drive's details is not
  /// asking for it to sync.
  testWidgets('offers the drive its own sync', (tester) async {
    await pumpPanel(tester);

    expect(synced, 0, reason: 'showing the details syncs nothing');

    await tester.tap(find.text('Sync Now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(synced, 1);

    await takeDown(tester);
  });

  testWidgets('and only says so where there is no sync to offer',
      (tester) async {
    await pumpPanel(tester, withSync: false);

    expect(find.text('Never synced'), findsOneWidget);
    expect(find.text('Sync Now'), findsNothing);

    await takeDown(tester);
  });

  /// It had no toolbar outside a loaded drive in the explorer, so nothing
  /// closed it there.
  testWidgets('closes through the close it is given', (tester) async {
    await pumpPanel(tester);

    await tester.tap(toolbarAction('Close'));
    await tester.pump();

    expect(closed, 1);

    await takeDown(tester);
  });

  /// None of its files are known, so there is nothing to download.
  testWidgets('offers no download for a drive never synced', (tester) async {
    await pumpPanel(tester);

    expect(toolbarAction('Close'), findsOneWidget);
    expect(toolbarAction('Download'), findsNothing);

    await takeDown(tester);
  });
}
