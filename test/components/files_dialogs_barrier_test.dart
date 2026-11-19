import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/components/fs_entry_move_form.dart';
import 'package:ardrive/components/fs_entry_rename_form.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Selectable;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../test_utils/utils.dart';

class _MockProfile extends MockCubit<ProfileState> implements ProfileCubit {}

class _MockSync extends MockCubit<SyncState> implements SyncCubit {}

class _MockTurbo extends Mock implements TurboUploadService {}

class _MockGlobalHide extends MockBloc<GlobalHideEvent, GlobalHideState>
    implements GlobalHideBloc {}

class _NeverSelectable extends Mock implements Selectable<Drive> {}

/// A dialog that does its work in place is not closed by a tap on the page
/// behind it.
void main() {
  Future<void> open(
    WidgetTester tester,
    void Function(BuildContext context) show,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final profile = _MockProfile();
    when(() => profile.state).thenReturn(
      ProfileLoggedIn(
        user: User(
          password: 'password',
          wallet: getTestWallet(),
          walletAddress: 'address',
          walletBalance: BigInt.one,
          cipherKey: SecretKey(List.filled(32, 7)),
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
        ),
        useTurbo: false,
      ),
    );
    final driveDao = MockDriveDao();
    final selectable = _NeverSelectable();
    when(() => selectable.getSingle())
        .thenAnswer((_) => Completer<Drive>().future);
    when(() => driveDao.driveById(driveId: any(named: 'driveId')))
        .thenReturn(selectable);
    final hide = _MockGlobalHide();
    whenListen(
      hide,
      const Stream<GlobalHideState>.empty(),
      initialState: const GlobalHideInitial(userHasHiddenDrive: false),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ActivityTracker>(
              create: (_) => ActivityTracker()),
          BlocProvider<ProfileCubit>.value(value: profile),
          BlocProvider<SyncCubit>.value(value: _MockSync()),
          BlocProvider<GlobalHideBloc>.value(value: hide),
          BlocProvider<DriveDetailCubit>.value(value: MockDriveDetailCubit()),
          Provider<ArweaveService>.value(value: MockArweaveService()),
          Provider<TurboUploadService>.value(value: _MockTurbo()),
          Provider<DriveDao>.value(value: driveDao),
        ],
        child: ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapBehind(WidgetTester tester) async {
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('rename stays open when the page behind is tapped',
      (tester) async {
    await open(
      tester,
      (context) => promptToRenameModal(
        context,
        driveId: 'drive',
        fileId: 'file',
        initialName: 'photo.png',
      ),
    );
    expect(find.byType(FsEntryRenameForm), findsOneWidget);

    await tapBehind(tester);

    expect(find.byType(FsEntryRenameForm), findsOneWidget);
  });

  testWidgets('move stays open when the page behind is tapped', (tester) async {
    await open(
      tester,
      (context) => promptToMove(
        context,
        driveId: 'drive',
        selectedItems: [createMockFileDataTableItem(name: 'a.txt')],
      ),
    );
    expect(find.byType(FsEntryMoveForm), findsOneWidget);

    await tapBehind(tester);

    expect(find.byType(FsEntryMoveForm), findsOneWidget);
  });
}
