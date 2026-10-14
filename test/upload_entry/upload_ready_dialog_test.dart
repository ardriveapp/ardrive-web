import 'dart:async';

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/models/models.dart';
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

/// The last step before the picker.
///
/// It says where the files are going and opens the picker, and that is all.
/// It reports nothing about syncing: a drive that has not been read is the
/// page's business, and a second report over the top of it made the reader
/// watch a sync they only wanted as a means to an upload.
void main() {
  final photos = _drive('photos', 'Photos');
  final website = _drive('website', 'Website', privacy: 'public');

  late MockDriveDetailCubit detail;
  late StreamController<DriveDetailState> detailStates;
  late List<String> chosen;

  DriveDetailLoadSuccess loaded(
    Drive drive, {
    String folderId = 'root',
    bool writable = true,
  }) {
    final entry = _FolderEntry();
    when(() => entry.id).thenReturn(folderId);

    final folder = _Folder();
    when(() => folder.folder).thenReturn(entry);

    final state = _Loaded();
    when(() => state.currentDrive).thenReturn(drive);
    when(() => state.hasWritePermissions).thenReturn(writable);
    when(() => state.folderInView).thenReturn(folder);
    return state;
  }

  setUp(() {
    detail = MockDriveDetailCubit();
    detailStates = StreamController<DriveDetailState>();
    chosen = [];
  });

  tearDown(() => detailStates.close());

  Future<void> open(
    WidgetTester tester, {
    required Drive drive,
    required DriveDetailState state,
    bool isFolderUpload = false,
    Size size = const Size(1200, 900),
    bool dark = false,
  }) async {
    whenListen(detail, detailStates.stream, initialState: state);

    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ArDriveTheme(
        // Passing no theme data is how ArDriveTheme yields the dark theme.
        themeData: dark ? null : lightTheme(),
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
                  builder: (_) => BlocProvider<DriveDetailCubit>.value(
                    value: detail,
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
    await tester.pumpAndSettle();
  }

  Finder dialogTitle(Drive drive) => find.text('Upload to ${drive.name}');

  /// The narrowest phone the app is drawn for. A dialog that sets a fixed
  /// content width overflows here, and an overflow throws in a test.
  testWidgets('fits a narrow phone', (tester) async {
    await open(
      tester,
      drive: photos,
      state: loaded(photos),
      size: const Size(320, 640),
    );

    expect(dialogTitle(photos), findsOneWidget);
    expect(find.text('Choose Files'), findsOneWidget);
  });

  testWidgets('and reads in the dark theme', (tester) async {
    await open(tester, drive: photos, state: loaded(photos), dark: true);

    expect(dialogTitle(photos), findsOneWidget);
    expect(find.text('Choose Files'), findsOneWidget);
  });

  /// A long drive name at twice the text size is taller than a short phone.
  /// The picker button has to survive that, or the dialog is a dead end.
  testWidgets('and the largest text a reader can ask for', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // The same drive the screen is showing: a dialog over any other drive
    // closes itself, which is what this test was really proving.
    final longName = _drive('holidays', 'Holidays and other long drive names');

    await open(
      tester,
      drive: longName,
      state: loaded(longName),
      size: const Size(320, 640),
    );

    expect(find.text('Choose Files'), findsOneWidget);
  });

  testWidgets('names the drive and says it is private', (tester) async {
    await open(tester, drive: photos, state: loaded(photos));

    expect(dialogTitle(photos), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
  });

  /// Public is permanent and visible to anyone, and this is the last moment
  /// to see it before files are chosen.
  testWidgets('and says when it is public', (tester) async {
    await open(tester, drive: website, state: loaded(website));

    expect(find.text('Public'), findsOneWidget);
  });

  testWidgets('closes and starts the upload into the folder in view',
      (tester) async {
    await open(
      tester,
      drive: photos,
      state: loaded(photos, folderId: 'holidays'),
    );

    await tester.tap(find.text('Choose Files'));
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    expect(chosen, isEmpty);
    expect(dialogTitle(photos), findsNothing);
  });

  group('closes itself rather than lingering', () {
    testWidgets('when the screen shows another drive', (tester) async {
      await open(tester, drive: photos, state: loaded(photos));

      detailStates.add(loaded(website));
      await tester.pumpAndSettle();

      expect(dialogTitle(photos), findsNothing);
      expect(chosen, isEmpty);
    });

    /// It never reports a sync, so a drive that stops being open is a drive
    /// this dialog has nothing to say about.
    testWidgets('when the drive stops being open', (tester) async {
      await open(tester, drive: photos, state: loaded(photos));

      detailStates.add(DriveDetailLoadUnsynced(drive: photos));
      await tester.pumpAndSettle();

      expect(dialogTitle(photos), findsNothing);
      expect(chosen, isEmpty);
    });

    testWidgets('when the drive cannot take files', (tester) async {
      await open(
        tester,
        drive: photos,
        state: loaded(photos, writable: false),
      );

      await tester.pumpAndSettle();

      expect(dialogTitle(photos), findsNothing);
    });
  });
}
