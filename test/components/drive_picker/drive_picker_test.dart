import 'package:ardrive/components/drive_picker/drive_picker_cubit.dart';
import 'package:ardrive/components/drive_picker/drive_picker_dialog.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Drive _drive(String id, {String privacy = 'public'}) => Drive(
      id: id,
      rootFolderId: 'root-$id',
      ownerAddress: 'owner',
      name: id == 'site' ? 'Website' : 'Photos',
      privacy: privacy,
      isHidden: false,
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
    );

final _site = _drive('site');
final _photos = _drive('photos', privacy: 'private');

const _campaigns = DrivePickerEntry(
  id: 'campaigns',
  name: 'Campaigns',
  contentType: 'folder',
);
const _logo = DrivePickerEntry(
  id: 'logo',
  name: 'logo.png',
  contentType: 'image/png',
);
const _pinned = DrivePickerEntry(
  id: 'pinned',
  name: 'theirs.pdf',
  contentType: 'application/pdf',
  isPinned: true,
);

/// A website drive: Campaigns at its root beside logo.png and a pinned
/// file; Campaigns holds nothing.
Future<DrivePickerFolder?> _read(Drive drive, String? folderId) async {
  if (drive.id != _site.id) return null;
  if (folderId == null || folderId == _site.rootFolderId) {
    return DrivePickerFolder(
      id: _site.rootFolderId,
      name: _site.name,
      parentFolderId: null,
      folders: const [_campaigns],
      files: const [_logo, _pinned],
    );
  }
  if (folderId == _campaigns.id) {
    return DrivePickerFolder(
      id: _campaigns.id,
      name: _campaigns.name,
      parentFolderId: _site.rootFolderId,
      folders: const [],
      files: const [],
    );
  }
  return null;
}

void main() {
  group('DrivePickerCubit', () {
    DrivePickerCubit build() =>
        DrivePickerCubit(drives: [_site, _photos], read: _read);

    blocTest<DrivePickerCubit, DrivePickerState>(
      'opens on the folder it is given',
      build: build,
      act: (cubit) => cubit.start(driveId: _site.id, folderId: _campaigns.id),
      skip: 1,
      expect: () => [
        isA<DrivePickerState>()
            .having((s) => s.drive, 'drive', _site)
            .having((s) => s.folder?.id, 'folder', _campaigns.id),
      ],
    );

    blocTest<DrivePickerCubit, DrivePickerState>(
      "a folder that has gone opens the drive's root",
      build: build,
      act: (cubit) => cubit.start(driveId: _site.id, folderId: 'moved-away'),
      verify: (cubit) {
        expect(cubit.state.folder?.id, _site.rootFolderId);
        expect(cubit.state.atRoot, isTrue);
      },
    );

    blocTest<DrivePickerCubit, DrivePickerState>(
      'a drive it was not given opens the list of drives',
      build: build,
      act: (cubit) => cubit.start(driveId: 'someone-elses'),
      expect: () => const <DrivePickerState>[],
      verify: (cubit) => expect(cubit.state.choosingDrive, isTrue),
    );

    blocTest<DrivePickerCubit, DrivePickerState>(
      'back goes up a folder, then from the root to the drives',
      build: build,
      act: (cubit) async {
        await cubit.start(driveId: _site.id, folderId: _campaigns.id);
        await cubit.back();
        expect(cubit.state.folder?.id, _site.rootFolderId);
        await cubit.back();
      },
      verify: (cubit) => expect(cubit.state.choosingDrive, isTrue),
    );

    blocTest<DrivePickerCubit, DrivePickerState>(
      'a drive not read on this device is said to be unreadable',
      build: build,
      act: (cubit) => cubit.openDrive(_photos),
      verify: (cubit) => expect(cubit.state.unreadable, isTrue),
    );

    blocTest<DrivePickerCubit, DrivePickerState>(
      'a file is chosen, and let go when chosen again',
      build: build,
      act: (cubit) async {
        await cubit.start(driveId: _site.id);
        cubit.chooseFile(_logo.id);
        expect(cubit.state.fileId, _logo.id);
        cubit.chooseFile(_logo.id);
      },
      verify: (cubit) => expect(cubit.state.fileId, isNull),
    );

    blocTest<DrivePickerCubit, DrivePickerState>(
      'opening a folder lets the chosen file go',
      build: build,
      act: (cubit) async {
        await cubit.start(driveId: _site.id);
        cubit.chooseFile(_logo.id);
        await cubit.openFolder(_campaigns.id);
      },
      verify: (cubit) => expect(cubit.state.fileId, isNull),
    );
  });

  group('DrivePickerDialog', () {
    DrivePickerChoice? chosen;

    setUp(() => chosen = null);

    Future<void> pump(
      WidgetTester tester, {
      List<Drive>? drives,
      String? driveId,
      bool Function(DrivePickerEntry file)? canChooseFile,
      bool showsPrivacy = false,
    }) async {
      final cubit = DrivePickerCubit(
        drives: drives ?? [_site, _photos],
        read: _read,
      );
      addTearDown(cubit.close);
      await tester.pumpWidget(
        ArDriveApp(
          themeData: lightTheme(),
          builder: (context) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: BlocProvider.value(
                        value: cubit,
                        child: DrivePickerDialog(
                          title: 'Pick',
                          canChooseFile: canChooseFile,
                          showsPrivacy: showsPrivacy,
                          actionLabel: (state) => state.fileId != null
                              ? 'Use file'
                              : state.folder == null
                                  ? 'Use'
                                  : state.atRoot
                                      ? 'Use drive'
                                      : 'Use folder',
                          onChoose: (choice) => chosen = choice,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await cubit.start(driveId: driveId);
      await tester.pumpAndSettle();
    }

    bool enabled(WidgetTester tester, String title) => tester
        .widget<DrivePickerRow>(
          find.ancestor(
            of: find.text(title),
            matching: find.byType(DrivePickerRow),
          ),
        )
        .enabled;

    bool actionDisabled(WidgetTester tester, String label) => tester
        .widget<ArDriveButtonNew>(find.widgetWithText(ArDriveButtonNew, label))
        .isDisabled;

    testWidgets('lists the drives, each saying public or private',
        (tester) async {
      await pump(tester, showsPrivacy: true);

      expect(find.text('Your drives'), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);
      expect(find.text('Public'), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
      // Nothing to act on until a drive is open.
      expect(actionDisabled(tester, 'Use'), isTrue);
      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();
      expect(chosen, isNull);
    });

    testWidgets('folder mode: files are shown greyed, the folder is chosen',
        (tester) async {
      await pump(tester, driveId: _site.id);

      expect(enabled(tester, 'logo.png'), isFalse);
      expect(enabled(tester, 'Campaigns'), isTrue);

      await tester.tap(find.text('Campaigns'));
      await tester.pumpAndSettle();
      expect(find.text('This folder is empty'), findsOneWidget);

      await tester.tap(find.text('Use folder'));
      await tester.pumpAndSettle();
      expect(chosen?.drive, _site);
      expect(chosen?.folder.id, _campaigns.id);
      expect(chosen?.fileId, isNull);
      expect(find.byType(DrivePickerDialog), findsNothing);
    });

    testWidgets('item mode: a file is chosen, the drive at its root',
        (tester) async {
      await pump(
        tester,
        driveId: _site.id,
        canChooseFile: (file) => !file.isPinned,
      );

      expect(actionDisabled(tester, 'Use drive'), isFalse);
      expect(enabled(tester, 'theirs.pdf'), isFalse);

      await tester.tap(find.text('logo.png'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use file'));
      await tester.pumpAndSettle();
      expect(chosen?.fileId, _logo.id);
      expect(chosen?.folder.id, _site.rootFolderId);
    });

    testWidgets('a file row shows its type icon, as the explorer does',
        (tester) async {
      await pump(tester, driveId: _site.id);

      final icon = tester
          .widget<DrivePickerRow>(find.ancestor(
            of: find.text('logo.png'),
            matching: find.byType(DrivePickerRow),
          ))
          .icon;
      expect(icon.icon, ArDriveIcons.image().icon);
    });

    testWidgets('a drive not read here says so, with nothing to choose',
        (tester) async {
      await pump(tester);

      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      expect(find.text('Not synced on this device'), findsOneWidget);
      expect(actionDisabled(tester, 'Use'), isTrue);
      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();
      expect(chosen, isNull);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Your drives'), findsOneWidget);
    });

    testWidgets('no drives: says so', (tester) async {
      await pump(tester, drives: const []);

      expect(find.text('No public drives yet'), findsOneWidget);
    });
  });
}
