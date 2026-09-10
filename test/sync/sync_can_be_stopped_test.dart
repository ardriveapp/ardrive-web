import 'dart:async';

import 'package:ardrive/components/app_top_bar.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:provider/provider.dart';

import '../test_utils/mocks.dart';

class _MockSyncCubit extends MockBloc<dynamic, SyncState>
    implements SyncCubit {}

/// A sync you can get out of.
///
/// The engine has always been able to stop one - both entry points carry a
/// cancellation token and both report SyncCancelled - but the only control
/// that ever asked for it was the blocking modal, and that went when sync
/// stopped taking the app away. A drive with a million transactions could then
/// be started and not stopped, which is the one case the feature exists for.
void main() {
  late _MockSyncCubit syncCubit;
  late MockDrivesCubit drivesCubit;
  late StreamController<SyncProgress> progress;

  setUp(() {
    syncCubit = _MockSyncCubit();
    drivesCubit = MockDrivesCubit();
    progress = StreamController<SyncProgress>.broadcast();

    when(() => syncCubit.syncProgressController).thenReturn(progress);
    when(() => syncCubit.syncProgress).thenReturn(SyncProgress.initial());
    when(() => syncCubit.syncStartTime).thenReturn(DateTime(2024));
    when(() => syncCubit.cancelSync()).thenReturn(null);
    whenListen(drivesCubit, const Stream<DrivesState>.empty(),
        initialState: DrivesLoadInProgress());
  });

  tearDown(() => progress.close());

  Future<void> pumpBar(WidgetTester tester, SyncState state) async {
    whenListen(syncCubit, const Stream<SyncState>.empty(), initialState: state);

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
          home: MultiProvider(
            providers: [
              ListenableProvider<AppRouterDelegate>.value(
                value: AppRouterDelegate(),
              ),
              BlocProvider<SyncCubit>.value(value: syncCubit),
              BlocProvider<DrivesCubit>.value(value: drivesCubit),
            ],
            child: const Portal(
              child: Scaffold(body: Center(child: SyncButton())),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a running sync can be stopped from where it is reported',
      (tester) async {
    await pumpBar(tester, SyncInProgress(trigger: SyncTrigger.userInitiated));

    await tester.tap(find.byType(SyncButton));
    // The ring rotates forever, so the tree never settles - and the menu
    // reveals through an offstage transition, so one pump is not enough for it
    // to accept a tap. Several fixed pumps get it fully open without waiting
    // on an animation that never ends.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(find.text('Stop syncing'), findsOneWidget);

    await tester.tap(find.text('Stop syncing'));
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => syncCubit.cancelSync()).called(1);
  });

  testWidgets('and nothing offers to stop one that is not running',
      (tester) async {
    await pumpBar(tester, SyncIdle());

    expect(
      find.text('Stop syncing'),
      findsNothing,
      reason: 'an idle indicator is not even drawn, let alone its menu',
    );
  });
}
