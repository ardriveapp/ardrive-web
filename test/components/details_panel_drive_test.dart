import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/entities/entities.dart';
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
  late MockArweaveService networkReads;

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

  /// The revisions reading a drive's contents leaves behind, which is what
  /// tells the panel this device knows what is in the drive.
  Future<void> markDriveRead() async {
    await db.into(db.folderRevisions).insert(
          FolderRevisionsCompanion.insert(
            folderId: rootFolderId,
            driveId: driveId,
            name: 'Photos',
            metadataTxId: 'folder-tx',
            action: RevisionAction.create,
          ),
        );
    await db.into(db.driveRevisions).insert(
          DriveRevisionsCompanion.insert(
            driveId: driveId,
            rootFolderId: rootFolderId,
            ownerAddress: fakeUserJson.walletAddress,
            name: 'Photos',
            privacy: DrivePrivacyTag.public,
            metadataTxId: 'drive-tx',
            action: RevisionAction.create,
          ),
        );
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    bool withSync = true,
    Future<List<DriveEntity>?> Function()? networkHistory,
  }) async {
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
    when(
      () => arweave.getDriveEntityRevisions(
        any(),
        ownerAddress: any(named: 'ownerAddress'),
        driveKey: any(named: 'driveKey'),
      ),
    ).thenAnswer((_) => networkHistory?.call() ?? Future.value(null));
    networkReads = arweave;

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

  /// Opens the Activity tab and lets its read finish, on the real clock.
  ///
  /// The tab's contents, and the cubit that reads its history, are built only
  /// once the tab is switched to. Built on the fake clock, its database reads
  /// never finish, and neither does closing them.
  Future<void> openActivity(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Activity'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
  }

  DriveEntity revision(String name, DateTime at, {bool isHidden = false}) =>
      DriveEntity(
        id: driveId,
        name: name,
        rootFolderId: rootFolderId,
        privacy: DrivePrivacyTag.public,
        authMode: DriveAuthModeTag.none,
        isHidden: isHidden,
      )
        ..ownerAddress = fakeUserJson.walletAddress
        ..txId = 'tx-$name-${at.millisecondsSinceEpoch}'
        ..createdAt = at;

  Finder toolbarAction(String tooltip) => find.byWidgetPredicate(
        (w) => w is ArDriveIconButton && w.tooltip == tooltip,
      );

  testWidgets('says what it knows, not a spinner', (tester) async {
    await pumpPanel(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Not synced on this device'), findsOneWidget);
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

    await tester.tap(find.text('Sync this drive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(synced, 1);

    await takeDown(tester);
  });

  testWidgets('and only says so where there is no sync to offer',
      (tester) async {
    await pumpPanel(tester, withSync: false);

    expect(find.text('Not synced on this device'), findsOneWidget);
    expect(find.text('Sync this drive'), findsNothing);

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

  /// The tab waited on history only a sync stores, and said "Loading..." for
  /// good. It reads the drive's own history from the network instead.
  group('the activity of a drive never synced', () {
    /// Runs [body] on the panel's Activity tab, and takes the panel down on
    /// the real clock even when [body] fails: left to the framework, closing
    /// its database streams never finishes and the run hangs.
    Future<void> onActivity(
      WidgetTester tester,
      Future<void> Function() body, {
      bool withSync = true,
      Future<List<DriveEntity>?> Function()? networkHistory,
    }) async {
      await pumpPanel(
        tester,
        withSync: withSync,
        networkHistory: networkHistory,
      );
      try {
        await openActivity(tester);
        await body();
      } finally {
        await takeDown(tester);
      }
    }

    testWidgets('lists its history from the network, newest first',
        (tester) async {
      await onActivity(
        tester,
        networkHistory: () async => [
          revision('Photos', DateTime(2025, 1, 1)),
          revision('Pics', DateTime(2025, 6, 1)),
        ],
        () async {
          final renamed = find.text('This drive was renamed to Pics.');
          final created =
              find.text('This drive was created with the name Photos.');
          expect(renamed, findsOneWidget);
          expect(created, findsOneWidget);
          expect(
            tester.getTopLeft(renamed).dy,
            lessThan(tester.getTopLeft(created).dy),
          );
          expect(find.text('No activity recorded yet.'), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
        },
      );
    });

    testWidgets('says to sync it when the history cannot be read',
        (tester) async {
      await onActivity(tester, networkHistory: () async => null, () async {
        expect(
          find.text('Sync this drive to see its activity.'),
          findsOneWidget,
        );
        expect(find.text('No activity recorded yet.'), findsNothing);

        // The same offer as the details tab, and it is the drive's own sync.
        final syncs = find.text('Sync this drive');
        expect(syncs, findsOneWidget);
        await tester.tap(syncs);
        await tester.pump();
        expect(synced, 1);
      });
    });

    testWidgets('offers no sync where there is none to offer', (tester) async {
      await onActivity(
        tester,
        withSync: false,
        networkHistory: () async => null,
        () async {
          expect(
            find.text('Sync this drive to see its activity.'),
            findsOneWidget,
          );
          expect(find.text('Sync this drive'), findsNothing);
        },
      );
    });

    testWidgets('a synced drive shows its own history and reads nothing',
        (tester) async {
      await tester.runAsync(() async {
        await markDriveRead();
        // What the activity joins each revision to.
        await db.into(db.networkTransactions).insert(
              NetworkTransactionsCompanion.insert(id: 'drive-tx'),
            );
      });

      await onActivity(
        tester,
        networkHistory: () async => [revision('Other', DateTime(2020))],
        () async {
          expect(
            find.text('This drive was created with the name Photos.'),
            findsOneWidget,
          );
          expect(find.textContaining('Other'), findsNothing);
          verifyNever(
            () => networkReads.getDriveEntityRevisions(
              any(),
              ownerAddress: any(named: 'ownerAddress'),
              driveKey: any(named: 'driveKey'),
            ),
          );
        },
      );
    });
  });

  /// The test above is one end of the rule. The read that decides it is a
  /// round trip, and these are the states the panel passes through on the way,
  /// where the drive's contents are just as unknown. Asked of the rule
  /// directly: the wait is over before a widget test can look at it.
  group('the download a drive is offered', () {
    late DriveDataItem driveItem;

    setUp(() {
      driveItem = DriveDataTableItemMapper.fromDrive(drive, (_) {}, 0, true);
    });

    test('is withheld while the read is in flight', () {
      expect(offersDownload(driveItem, FsEntryInfoInitial()), isFalse);
    });

    test('is withheld when the read fails', () {
      expect(offersDownload(driveItem, FsEntryInfoFailure()), isFalse);
    });

    /// And is made once the read says the drive has contents here, which is
    /// every drive the explorer shows. Through the cubit the panel uses, so
    /// the rule is tied to the state it really emits.
    test('is made once the read says the drive has contents', () async {
      await markDriveRead();

      final info = FsEntryInfoCubit(
        driveId: driveId,
        maybeSelectedItem: driveItem,
        driveDao: db.driveDao,
        licenseService: MockLicenseService(),
        arweave: MockArweaveService(),
      );
      addTearDown(info.close);

      final state = await info.stream.first;

      expect(state, isA<FsEntryDriveInfoSuccess>());
      expect(offersDownload(driveItem, state), isTrue);
    });

    test('is made for a file whatever the panel has read', () {
      final file = createMockFileDataTableItem();

      expect(offersDownload(file, FsEntryInfoInitial()), isTrue);
      expect(offersDownload(file, FsEntryInfoFailure()), isTrue);
    });
  });
}
