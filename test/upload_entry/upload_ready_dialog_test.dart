import 'dart:async';

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/upload_entry/presentation/upload_ready_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

class _Loaded extends Mock implements DriveDetailLoadSuccess {}

class _Folder extends Mock implements FolderWithContents {}

class _FolderEntry extends Mock implements FolderEntry {}

Drive _drive(String id, String name, {String privacy = 'private'}) => Drive(
      id: id,
      rootFolderId: 'root-$id',
      ownerAddress: 'owner',
      name: name,
      privacy: privacy,
      isHidden: false,
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
    );

/// The dialog Upload opens for a drive that is not open yet.
///
/// Every state has to say where the files will go and what happens next, and
/// nothing it offers may be a button that does nothing.
void main() {
  final photos = _drive('photos', 'Photos');
  final website = _drive('website', 'Website', privacy: 'public');

  late MockDriveDetailCubit detail;
  late MockSyncBloc sync;
  late StreamController<DriveDetailState> detailStates;
  late List<String> chosen;

  DriveDetailLoadSuccess loaded(Drive drive, {String folderId = 'root'}) {
    final entry = _FolderEntry();
    when(() => entry.id).thenReturn(folderId);

    final folder = _Folder();
    when(() => folder.folder).thenReturn(entry);

    final state = _Loaded();
    when(() => state.currentDrive).thenReturn(drive);
    when(() => state.hasWritePermissions).thenReturn(true);
    when(() => state.folderInView).thenReturn(folder);
    return state;
  }

  setUp(() {
    detail = MockDriveDetailCubit();
    sync = MockSyncBloc();
    detailStates = StreamController<DriveDetailState>();
    chosen = [];

    when(() => detail.syncCurrentDrive()).thenAnswer((_) async {});
    when(() => sync.syncingDriveId).thenReturn(null);
    when(() => sync.syncingDriveIds).thenReturn(null);
    when(() => sync.completedDriveIds).thenReturn(const []);
    whenListen(sync, const Stream<SyncState>.empty(), initialState: SyncIdle());
  });

  tearDown(() => detailStates.close());

  /// A progress indicator never settles, so frames are pumped rather than
  /// waited out.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(
    WidgetTester tester, {
    required Drive drive,
    required DriveDetailState state,
    bool isFolderUpload = false,
  }) async {
    whenListen(detail, detailStates.stream, initialState: state);

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => MultiBlocProvider(
                    providers: [
                      BlocProvider<DriveDetailCubit>.value(value: detail),
                      BlocProvider<SyncCubit>.value(value: sync),
                    ],
                    child: UploadReadyDialog(
                      drive: drive,
                      isFolderUpload: isFolderUpload,
                      onChoose: chosen.add,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await settle(tester);
  }

  ArDriveButtonNew button(WidgetTester tester, String text) =>
      tester.widget<ArDriveButtonNew>(
        find.widgetWithText(ArDriveButtonNew, text),
      );

  Finder dialogTitle(Drive drive) => find.text('Upload to ${drive.name}');

  group('names where the files will go', () {
    testWidgets('and that the drive is private', (tester) async {
      await open(tester, drive: photos, state: loaded(photos));

      expect(dialogTitle(photos), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);
    });

    /// Public is permanent and visible to anyone. It is said before anything
    /// is chosen.
    testWidgets('and that the drive is public', (tester) async {
      await open(tester, drive: website, state: loaded(website));

      expect(find.text('Public'), findsOneWidget);
    });
  });

  group('a drive that is ready', () {
    testWidgets('closes and starts the upload into the folder in view',
        (tester) async {
      await open(
        tester,
        drive: photos,
        state: loaded(photos, folderId: 'holidays'),
      );

      await tester.tap(find.text('Choose Files'));
      await settle(tester);

      expect(chosen, ['holidays']);
      expect(dialogTitle(photos), findsNothing);
    });

    testWidgets('offers a folder when a folder was asked for', (tester) async {
      await open(
        tester,
        drive: photos,
        state: loaded(photos),
        isFolderUpload: true,
      );

      expect(find.text('Choose Folder'), findsOneWidget);
      expect(find.text('Choose Files'), findsNothing);
    });

    testWidgets('can be cancelled without starting anything', (tester) async {
      await open(tester, drive: photos, state: loaded(photos));

      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(chosen, isEmpty);
      expect(dialogTitle(photos), findsNothing);
    });
  });

  group('a drive nothing has read', () {
    testWidgets('says why and offers its sync', (tester) async {
      await open(
        tester,
        drive: photos,
        state: DriveDetailLoadUnsynced(drive: photos),
      );

      expect(
        find.text("Photos isn't synced on this device yet. "
            'Sync it to add files.'),
        findsOneWidget,
      );
      expect(button(tester, 'Sync This Drive').isDisabled, isFalse);

      await tester.tap(find.text('Sync This Drive'));
      await settle(tester);

      verify(() => detail.syncCurrentDrive()).called(1);
      expect(
        dialogTitle(photos),
        findsOneWidget,
        reason: 'the dialog stays with the reader through the sync',
      );
    });

    /// One sync at a time and no queue. The button is drawn as unavailable,
    /// and pressing it does nothing rather than asking for a refused sync.
    testWidgets('holds its sync while another drive syncs', (tester) async {
      whenListen(sync, const Stream<SyncState>.empty(),
          initialState: SyncInProgress());
      when(() => sync.syncingDriveId).thenReturn('another-drive');

      await open(
        tester,
        drive: photos,
        state: DriveDetailLoadUnsynced(drive: photos),
      );

      expect(
        find.text('Another drive is syncing. '
            'You can sync Photos once it finishes.'),
        findsOneWidget,
      );
      expect(button(tester, 'Sync This Drive').isDisabled, isTrue);

      await tester.tap(find.text('Sync This Drive'));
      await settle(tester);

      verifyNever(() => detail.syncCurrentDrive());
    });

    testWidgets('offers to check again once a sync has found nothing',
        (tester) async {
      await open(
        tester,
        drive: photos,
        state: DriveDetailLoadUnsynced(drive: photos, syncFoundNothing: true),
      );

      expect(find.text('Close'), findsOneWidget);

      await tester.tap(find.text('Check Again'));
      await settle(tester);

      verify(() => detail.syncCurrentDrive()).called(1);
    });

    /// The whole point: the reader never has to go and find a Sync button,
    /// and never has to press Upload twice.
    testWidgets('moves on to choosing files as soon as the drive opens',
        (tester) async {
      await open(
        tester,
        drive: photos,
        state: DriveDetailLoadUnsynced(drive: photos),
      );

      detailStates.add(loaded(photos));
      await settle(tester);

      expect(find.text('Choose Files'), findsOneWidget);
      expect(button(tester, 'Choose Files').isDisabled, isFalse);
    });
  });

  group('a drive being synced', () {
    testWidgets('shows it, and says Close rather than Cancel', (tester) async {
      whenListen(sync, const Stream<SyncState>.empty(),
          initialState: SyncInProgress());
      when(() => sync.syncingDriveId).thenReturn(photos.id);

      await open(tester, drive: photos, state: DriveDetailLoadInProgress());

      expect(find.text('Syncing Photos...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.text('Close'),
        findsOneWidget,
        reason: 'closing the dialog does not stop the sync',
      );
      expect(find.text('Cancel'), findsNothing);
      expect(button(tester, 'Choose Files').isDisabled, isTrue);
    });
  });

  testWidgets('a drive being opened says so', (tester) async {
    await open(tester, drive: photos, state: DriveDetailLoadInProgress());

    expect(find.text('Opening Photos...'), findsOneWidget);
    expect(button(tester, 'Choose Files').isDisabled, isTrue);
  });

  testWidgets('closes itself once the screen shows another drive',
      (tester) async {
    await open(
      tester,
      drive: photos,
      state: DriveDetailLoadUnsynced(drive: photos),
    );

    detailStates.add(loaded(website));
    await settle(tester);

    expect(dialogTitle(photos), findsNothing);
    expect(chosen, isEmpty);
  });
}
