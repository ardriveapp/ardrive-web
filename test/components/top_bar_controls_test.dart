import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/components/app_top_bar.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/presentation/sync_elapsed_time.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

class _MockGlobalHideBloc extends MockBloc<GlobalHideEvent, GlobalHideState>
    implements GlobalHideBloc {}

/// The desktop top bar's row, shared by Your drives and a drive (#47).
void main() {
  late _MockGlobalHideBloc hideBloc;
  late MockSyncBloc syncCubit;
  late MockDrivesCubit drivesCubit;
  late MockProfileCubit profileCubit;
  late StreamController<SyncProgress> progress;

  setUp(() {
    hideBloc = _MockGlobalHideBloc();
    syncCubit = MockSyncBloc();
    drivesCubit = MockDrivesCubit();
    profileCubit = MockProfileCubit();
    progress = StreamController<SyncProgress>.broadcast();
    whenListen(hideBloc, const Stream<GlobalHideState>.empty(),
        initialState: const HiddingItems(userHasHiddenDrive: true));
    whenListen(syncCubit, const Stream<SyncState>.empty(),
        initialState: SyncIdle());
    when(() => syncCubit.syncProgressController).thenReturn(progress);
    when(() => syncCubit.syncProgress).thenReturn(SyncProgress.initial());
    when(() => syncCubit.syncingDriveId).thenReturn(null);
    when(() => syncCubit.syncingDriveIds).thenReturn(null);
    whenListen(drivesCubit, const Stream<DrivesState>.empty(),
        initialState: DrivesLoadInProgress());
    whenListen(profileCubit, const Stream<ProfileState>.empty(),
        initialState: ProfileLoggingOut());
  });

  tearDown(() => progress.close());

  Widget host(Widget child) => Portal(
        child: ArDriveTheme(
          themeData: lightTheme(),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<GlobalHideBloc>.value(value: hideBloc),
              BlocProvider<SyncCubit>.value(value: syncCubit),
              BlocProvider<DrivesCubit>.value(value: drivesCubit),
              BlocProvider<ProfileCubit>.value(value: profileCubit),
            ],
            child: MaterialApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en', '')],
              home: Scaffold(body: Center(child: child)),
            ),
          ),
        ),
      );

  group('the shared row', () {
    Future<void> pumpRow(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const SizedBox(
        width: 1000,
        child: TopBarControls(
          search: SizedBox(
            key: Key('search'),
            width: double.infinity,
            height: 40,
          ),
        ),
      )));
    }

    testWidgets('caps search at 400 and puts it on the left', (tester) async {
      await pumpRow(tester);

      final search = tester.getRect(find.byKey(const Key('search')));
      final row = tester.getRect(find.byType(TopBarControls));
      expect(search.width, TopBarControls.searchMaxWidth);
      expect(search.left, row.left);
    });

    // B4: Phil moved showing hidden items to the explorer's columns menu.
    testWidgets('has no hidden-items eye', (tester) async {
      await pumpRow(tester);

      expect(find.byIcon(ArDriveIcons.eyeClosed().icon), findsNothing);
      expect(find.byIcon(ArDriveIcons.eyeOpen().icon), findsNothing);
    });

    testWidgets('the sync slot carries the 16 px gap to the profile card',
        (tester) async {
      await pumpRow(tester);
      final profile = tester.getRect(find.byType(ProfileCard));
      final sync = tester.getRect(find.byType(SyncButton));

      expect(
        profile.left - sync.right,
        0,
        reason: 'the 16 px gap belongs to the sync slot',
      );
    });
  });

  // #52: "-3s elapsed" after a sync was stopped and the next started at once.
  testWidgets('elapsed time is never negative', (tester) async {
    late String text;
    await tester.pumpWidget(host(Builder(builder: (context) {
      text = formatSyncElapsed(context, const Duration(seconds: -3));
      return const SizedBox();
    })));

    expect(text, isNot(contains('-')));
    expect(text, contains('0'));
  });
}
