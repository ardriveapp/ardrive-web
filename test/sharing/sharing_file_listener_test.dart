import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/drive_picker/drive_picker_cubit.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sharing/blocs/sharing_file_bloc.dart';
import 'package:ardrive/sharing/sharing_file_listener.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:drift/drift.dart' show Selectable;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../test_utils/mocks.dart';

class _MockSharingFileBloc extends MockBloc<SharingFileEvent, SharingFileState>
    implements SharingFileBloc {}

class _MockFile extends Mock implements IOFile {}

class _MockUser extends Mock implements User {}

class _LoggedIn extends Mock implements ProfileLoggedIn {}

class _MockDrives extends Mock implements Selectable<Drive> {}

Drive _drive(String id, String name, {String owner = 'owner'}) => Drive(
      id: id,
      rootFolderId: 'root-$id',
      ownerAddress: owner,
      name: name,
      privacy: 'private',
      isHidden: false,
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
    );

/// A file shared into the app: one picker chooses its drive and folder,
/// where there used to be a file list, a drive step and a folder step.
void main() {
  setUpAll(() => registerFallbackValue(SharingFileCleared()));

  late _MockSharingFileBloc bloc;
  late StreamController<SharingFileState> shares;
  late List<
      ({
        String driveId,
        String parentFolderId,
        List<IOFile>? files,
        Drive? drive
      })> uploads;

  Future<void> pumpShare(
    WidgetTester tester, {
    DrivesState? drivesState,
    List<Drive> held = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    bloc = _MockSharingFileBloc();
    shares = StreamController<SharingFileState>.broadcast();
    addTearDown(shares.close);
    uploads = [];
    whenListen(bloc, shares.stream, initialState: SharingFileInitial());

    final user = _MockUser();
    when(() => user.walletAddress).thenReturn('owner');
    final loggedIn = _LoggedIn();
    when(() => loggedIn.user).thenReturn(user);
    final profile = MockProfileCubit();
    when(() => profile.state).thenReturn(loggedIn);
    final sync = MockSyncBloc();
    when(() => sync.state).thenReturn(SyncIdle());
    final drives = MockDrivesCubit();
    when(() => drives.state).thenReturn(drivesState ??
        DrivesLoadSuccess(
          selectedDriveId: 'a',
          userDrives: [_drive('a', 'Photos'), _drive('b', 'Archive')],
          sharedDrives: const [],
          drivesWithAlerts: const [],
          canCreateNewDrive: true,
        ));
    final dao = MockDriveDao();
    final selectable = _MockDrives();
    when(selectable.get).thenAnswer((_) async => held);
    when(dao.allDrives).thenReturn(selectable);

    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: MultiRepositoryProvider(
            providers: [
              ListenableProvider<ActivityTracker>.value(
                  value: ActivityTracker()),
              RepositoryProvider<DriveDao>.value(value: dao),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<SharingFileBloc>.value(value: bloc),
                BlocProvider<ProfileCubit>.value(value: profile),
                BlocProvider<SyncCubit>.value(value: sync),
                BlocProvider<DrivesCubit>.value(value: drives),
              ],
              child: Builder(
                builder: (context) => Scaffold(
                  body: SharingFileListener(
                    context: context,
                    prompt: (
                      context, {
                      required driveId,
                      required parentFolderId,
                      required isFolderUpload,
                      drive,
                      files,
                    }) async {
                      uploads.add((
                        driveId: driveId,
                        parentFolderId: parentFolderId,
                        files: files,
                        drive: drive,
                      ));
                    },
                    read: (drive, folderId) async => DrivePickerFolder(
                      id: folderId ?? drive.rootFolderId,
                      name: drive.name,
                      parentFolderId: null,
                      folders: const [],
                      files: const [],
                    ),
                    child: const SizedBox(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a shared file opens one picker, titled for what is shared',
      (tester) async {
    await pumpShare(tester);
    shares.add(SharingFileReceivedState([_MockFile()]));
    await tester.pumpAndSettle();

    expect(find.text('Upload 1 shared file'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Select drive'), findsNothing);
    expect(find.text('Share file'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verify(() => bloc.add(any(that: isA<SharingFileCleared>()))).called(1);
    expect(uploads, isEmpty);
  });

  testWidgets('choosing a drive and its folder uploads the files there, once',
      (tester) async {
    await pumpShare(tester);
    final file = _MockFile();
    shares.add(SharingFileReceivedState([file]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload here'));
    await tester.pumpAndSettle();

    expect(uploads.length, 1);
    expect(uploads.single.driveId, 'b');
    expect(uploads.single.parentFolderId, 'root-b');
    expect(uploads.single.files, [file]);
    expect(uploads.single.drive?.id, 'b');
    verify(() => bloc.add(any(that: isA<SharingFileCleared>()))).called(1);
  });

  testWidgets('a second share after the first still opens the picker',
      (tester) async {
    await pumpShare(tester);
    shares.add(SharingFileReceivedState([_MockFile()]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Upload 1 shared file'), findsNothing);

    shares.add(SharingFileReceivedState([_MockFile(), _MockFile()]));
    await tester.pumpAndSettle();

    expect(find.text('Upload 2 shared files'), findsOneWidget);
  });

  testWidgets(
      'before the drive list loads, only drives the wallet owns are offered',
      (tester) async {
    await pumpShare(
      tester,
      drivesState: DrivesLoadInProgress(),
      held: [
        _drive('a', 'Mine'),
        _drive('c', 'Someone elses', owner: 'other'),
      ],
    );
    shares.add(SharingFileReceivedState([_MockFile()]));
    await tester.pumpAndSettle();

    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Someone elses'), findsNothing);
  });
}
