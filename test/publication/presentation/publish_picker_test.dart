import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/drive_picker/drive_picker_cubit.dart';
import 'package:ardrive/components/drive_picker/drive_picker_dialog.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/publication/presentation/publish_to_web.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:drift/drift.dart' show Selectable;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../../test_utils/utils.dart';

class _MockActivityTracker extends Mock implements ActivityTracker {}

class _MockFolders extends Mock implements Selectable<FolderEntry> {}

class _MockFiles extends Mock implements Selectable<FileEntry> {}

Drive _drive(String id, String name, {bool hidden = false}) => Drive(
      id: id,
      rootFolderId: '$id-root',
      ownerAddress: 'owner',
      name: name,
      privacy: 'public',
      isHidden: hidden,
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
    );

final _site = _drive('site', 'Website');
final _archive = _drive('archive', 'Old archive', hidden: true);
final _blog = _drive('blog', 'Blog');

FileEntry _file(String id, String name, {String? pinnedBy}) => FileEntry(
      id: id,
      driveId: _site.id,
      name: name,
      parentFolderId: _site.rootFolderId,
      path: '',
      size: 1,
      lastModifiedDate: DateTime(2026),
      dataContentType: 'image/png',
      dataTxId: '$id-data',
      pinnedDataOwnerAddress: pinnedBy,
      isHidden: false,
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
    );

/// Publish on the Web pages page, through the code it really runs: which
/// drives it offers and which files can be chosen.
void main() {
  group('publishPickerDrives', () {
    test('offers the drives that can publish, leaving hidden ones out', () {
      expect(
        publishPickerDrives(
          [_site, _archive, _blog],
          canPublish: (drive) => drive != _blog,
        ),
        [_site],
      );
    });
  });

  test("a pinned file can't be chosen: its data is someone else's", () {
    const pinned = DrivePickerEntry(
        id: 'p', name: 'p.png', contentType: 'image/png', isPinned: true);
    const own =
        DrivePickerEntry(id: 'o', name: 'o.png', contentType: 'image/png');
    expect(publishPickerCanChooseFile(pinned), isFalse);
    expect(publishPickerCanChooseFile(own), isTrue);
  });

  group('pickAndPublishToWeb', () {
    late MockDrivesCubit drives;
    late MockSyncBloc sync;
    late MockDriveDao driveDao;
    late AppRouterDelegate router;

    setUp(() {
      drives = MockDrivesCubit();
      whenListen(
        drives,
        const Stream<DrivesState>.empty(),
        initialState: DrivesLoadSuccess(
          selectedDriveId: _site.id,
          userDrives: [_site, _archive, _blog],
          sharedDrives: const [],
          drivesWithAlerts: const [],
          canCreateNewDrive: true,
        ),
      );
      sync = MockSyncBloc();
      whenListen(sync, const Stream<SyncState>.empty(),
          initialState: SyncIdle());
      driveDao = MockDriveDao();
      final root = FolderEntry(
        id: _site.rootFolderId,
        driveId: _site.id,
        name: _site.name,
        path: '',
        dateCreated: DateTime(2026),
        lastUpdated: DateTime(2026),
        isGhost: false,
        isHidden: false,
      );
      final one = _MockFolders();
      when(() => one.getSingleOrNull()).thenAnswer((_) async => root);
      when(() => driveDao.folderById(folderId: root.id)).thenReturn(one);
      final folders = _MockFolders();
      when(() => folders.get()).thenAnswer((_) async => const []);
      when(() => driveDao.foldersInFolder(
          driveId: _site.id, parentFolderId: root.id)).thenReturn(folders);
      final files = _MockFiles();
      when(() => files.get()).thenAnswer((_) async => [
            _file('logo', 'logo.png'),
            _file('theirs', 'theirs.png', pinnedBy: 'someone'),
          ]);
      when(() => driveDao.filesInFolder(
          driveId: _site.id, parentFolderId: root.id)).thenReturn(files);
      router = AppRouterDelegate()
        ..showingWebPages = true
        ..driveId = _site.id;
    });

    Future<void> openPicker(WidgetTester tester) async {
      await tester.pumpWidget(
        ArDriveApp(
          themeData: lightTheme(),
          builder: (context) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider<AppRouterDelegate>.value(value: router),
                BlocProvider<DrivesCubit>.value(value: drives),
                BlocProvider<SyncCubit>.value(value: sync),
                RepositoryProvider<DriveDao>.value(value: driveDao),
                ListenableProvider<ActivityTracker>.value(
                  value: _MockActivityTracker(),
                ),
              ],
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    // Every drive here is public and its owner's.
                    onPressed: () =>
                        pickAndPublishToWeb(context, canPublish: (_) => true),
                    child: const Text('Publish'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();
    }

    bool rowEnabled(WidgetTester tester, String title) => tester
        .widget<DrivePickerRow>(find.ancestor(
            of: find.text(title), matching: find.byType(DrivePickerRow)))
        .enabled;

    testWidgets('opens on the drive last open; pinned files greyed',
        (tester) async {
      await openPicker(tester);

      expect(find.text('Publish to web'), findsOneWidget);
      expect(find.text('Publish drive'), findsOneWidget);
      expect(rowEnabled(tester, 'logo.png'), isTrue);
      expect(rowEnabled(tester, 'theirs.png'), isFalse);
    });

    testWidgets('lists no hidden drive', (tester) async {
      await openPicker(tester);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Website'), findsOneWidget);
      expect(find.text('Blog'), findsOneWidget);
      expect(find.text('Old archive'), findsNothing);
    });
  });
}
