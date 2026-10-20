import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/fake_user.dart';
import '../test_utils/utils.dart';

/// A file's details and history, for a file with two versions.
///
/// The ID rows showed a copy button and nothing to say which ID it copied,
/// and the history read "A new version of this file was uploaded." once per
/// version, with no number and no size to tell them apart.
void main() {
  const driveId = 'drive';
  const folderId = 'folder';
  const fileId = '3f2a9c4e-5b6d-4e8f-9a0b-1c2d3e4f7d1e';
  const firstTx = 'e-Qu1xAbCdEfGhIjKlMnOpQrStUvWxYz0123456k9Z2';
  const secondTx = 'jF3uAbCdEfGhIjKlMnOpQrStUvWxYz0123456789w7Lp';

  late Database db;
  late Drive drive;
  late FileEntry file;
  late MockArDriveAuth auth;

  Future<void> writeVersion({
    required int size,
    required String metadataTxId,
    required DateTime createdAt,
    required String action,
  }) async {
    final entity = FileEntity(
      id: fileId,
      driveId: driveId,
      parentFolderId: folderId,
      name: 'notes.txt',
      dataTxId: 'data$metadataTxId',
      size: size,
      lastModifiedDate: DateTime.utc(2026),
      dataContentType: 'application/octet-stream',
    )
      ..txId = metadataTxId
      ..createdAt = createdAt;

    await db.driveDao.transaction(() async {
      await db.driveDao.writeFileEntity(entity);
      await db.driveDao.insertFileRevision(
        entity.toRevisionCompanion(performedAction: action),
      );
    });
  }

  setUp(() async {
    db = getTestDb();
    auth = MockArDriveAuth();
    when(() => auth.currentUser).thenReturn(fakeUserJson);

    await db.into(db.drives).insert(
          DrivesCompanion.insert(
            id: driveId,
            rootFolderId: folderId,
            ownerAddress: fakeUserJson.walletAddress,
            name: 'Notes',
            privacy: DrivePrivacyTag.public,
          ),
        );
    drive = await db.driveDao.driveById(driveId: driveId).getSingle();

    await writeVersion(
      size: 640,
      metadataTxId: firstTx,
      createdAt: DateTime.utc(2026, 10, 20, 5, 44, 47),
      action: RevisionAction.create,
    );
    await writeVersion(
      size: 918,
      metadataTxId: secondTx,
      createdAt: DateTime.utc(2026, 10, 20, 5, 46, 35),
      action: RevisionAction.uploadNewVersion,
    );
    file = await db.driveDao.fileById(fileId: fileId).getSingle();
  });

  tearDown(() => db.close());

  Future<void> pumpPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final config = MockConfigService();
    when(() => config.config).thenReturn(
      AppConfig(allowedDataItemSizeForTurbo: 0, stripePublishableKey: ''),
    );

    final sync = MockSyncBloc();
    whenListen(
      sync,
      const Stream<SyncState>.empty(),
      initialState: SyncIdle(),
    );

    // On the real clock: the panel's cubits read the database, and that work
    // never finishes on the test's fake one.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<DriveDao>.value(value: db.driveDao),
            RepositoryProvider<ArweaveService>.value(
              value: MockArweaveService(),
            ),
            RepositoryProvider<LicenseService>.value(
              value: MockLicenseService(),
            ),
            RepositoryProvider<ConfigService>.value(value: config),
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
                        item: FileDataTableItem(
                          driveId: driveId,
                          fileId: fileId,
                          parentFolderId: folderId,
                          name: file.name,
                          size: file.size,
                          lastUpdated: file.lastUpdated,
                          dateCreated: file.dateCreated,
                          lastModifiedDate: file.lastModifiedDate,
                          contentType: 'application/octet-stream',
                          dataTxId: file.dataTxId,
                          metadataTx: null,
                          dataTx: null,
                          pinnedDataOwnerAddress: null,
                          index: 0,
                          isOwner: true,
                        ),
                        currentDrive: drive,
                        canNavigateThroughImages: false,
                        onClose: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  Future<void> openTab(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    // Built by this frame, and read from the database after it.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    // Not settled: the preview's spinner never stops in a test.
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> takeDown(WidgetTester tester) => tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

  testWidgets('shows each ID it offers to copy', (tester) async {
    await pumpPanel(tester);
    await openTab(tester, 'Details');

    expect(find.text('3f2a9c...7d1e'), findsOneWidget);
    expect(find.text('datajF...w7Lp'), findsOneWidget);
    expect(find.text('jF3uAb...w7Lp'), findsOneWidget);

    await takeDown(tester);
  });

  // The Activity tab's own read does not finish in a widget test, so the
  // numbering is asked of the rows that read returns.
  test('numbers the versions from the oldest', () async {
    await db.driveDao.transaction(() async {
      final renamed = FileEntity(
        id: fileId,
        driveId: driveId,
        parentFolderId: folderId,
        name: 'renamed.txt',
        dataTxId: 'data$secondTx',
        size: 918,
        lastModifiedDate: DateTime.utc(2026),
        dataContentType: 'application/octet-stream',
      )
        ..txId = 'renameTx'
        ..createdAt = DateTime.utc(2026, 10, 20, 6);
      await db.driveDao.insertFileRevision(
        renamed.toRevisionCompanion(performedAction: RevisionAction.rename),
      );
    });

    final revisions = await db.driveDao
        .latestFileRevisionsByFileIdWithLicenseAndTransactions(
          driveId: driveId,
          fileId: fileId,
        )
        .get();

    // Newest first: the rename, the second version, the first.
    expect(revisions.map((r) => r.action), [
      RevisionAction.rename,
      RevisionAction.uploadNewVersion,
      RevisionAction.create,
    ]);
    expect(fileVersionNumbers(revisions), {1: 2, 2: 1});
  });

  group('shortenId', () {
    test('keeps the start and the end of a long ID', () {
      expect(shortenId(fileId), '3f2a9c...7d1e');
      expect(shortenId(firstTx), 'e-Qu1x...k9Z2');
    });

    test('leaves an ID that is already short', () {
      expect(shortenId('abc'), 'abc');
      expect(shortenId('abcdefghijklm'), 'abcdefghijklm');
    });
  });
}
