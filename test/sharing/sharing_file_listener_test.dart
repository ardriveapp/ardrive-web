import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sharing/blocs/sharing_file_bloc.dart';
import 'package:ardrive/sharing/sharing_file_listener.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

class _MockSharingFileBloc extends MockBloc<SharingFileEvent, SharingFileState>
    implements SharingFileBloc {}

class _MockFile extends Mock implements IOFile {}

class _LoggedIn extends Mock implements ProfileLoggedIn {}

Drive _drive(String id, String name) => Drive(
      id: id,
      rootFolderId: 'root-$id',
      ownerAddress: 'owner',
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

  testWidgets('a shared file opens one picker, titled for what is shared',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final bloc = _MockSharingFileBloc();
    final file = _MockFile();
    whenListen(
      bloc,
      Stream<SharingFileState>.value(SharingFileReceivedState([file])),
      initialState: SharingFileInitial(),
    );
    final profile = MockProfileCubit();
    when(() => profile.state).thenReturn(_LoggedIn());
    final sync = MockSyncBloc();
    when(() => sync.state).thenReturn(SyncIdle());
    final drives = MockDrivesCubit();
    when(() => drives.state).thenReturn(DrivesLoadSuccess(
      selectedDriveId: 'a',
      userDrives: [_drive('a', 'Photos'), _drive('b', 'Archive')],
      sharedDrives: const [],
      drivesWithAlerts: const [],
      canCreateNewDrive: true,
    ));

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
              RepositoryProvider<DriveDao>.value(value: MockDriveDao())
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
                    child: const SizedBox(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Upload 1 shared file'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Select drive'), findsNothing);
    expect(find.text('Share file'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verify(() => bloc.add(any(that: isA<SharingFileCleared>()))).called(1);
  });
}
