import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/progress_dialog.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/presentation/sync_overlay.dart';
import 'package:ardrive/sync/presentation/sync_summary.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../../test_utils/mocks.dart';

void main() {
  late MockSyncBloc syncCubit;
  late MockProfileCubit profileCubit;
  late MockConfigService configService;
  late StreamController<SyncProgress> progressController;

  setUp(() {
    syncCubit = MockSyncBloc();
    profileCubit = MockProfileCubit();
    configService = MockConfigService();
    progressController = StreamController<SyncProgress>.broadcast();

    when(() => syncCubit.syncProgressController).thenReturn(progressController);
    when(() => syncCubit.syncProgress).thenReturn(SyncProgress.initial());
    when(() => syncCubit.syncStartTime).thenReturn(DateTime.now());
    when(() => profileCubit.state).thenReturn(ProfileCheckingAvailability());
    when(() => profileCubit.isCurrentProfileArConnect())
        .thenAnswer((_) async => false);
    // Production keeps the gateway banner - a debug affordance - out of the way.
    when(() => configService.flavor).thenReturn(Flavor.production);
  });

  tearDown(() async {
    await progressController.close();
  });

  Widget wrap(SyncState syncState) {
    return Portal(
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
            body: MultiBlocProvider(
              providers: [
                BlocProvider<SyncCubit>.value(value: syncCubit),
                BlocProvider<ProfileCubit>.value(value: profileCubit),
              ],
              child: Provider<ConfigService>.value(
                value: configService,
                child: SyncOverlay(syncState: syncState),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a sync nobody asked for paints nothing over the app',
      (tester) async {
    await tester.pumpWidget(
      wrap(SyncInProgress(trigger: SyncTrigger.background)),
    );
    await tester.pump();

    expect(find.byType(SyncScrim), findsNothing);
    expect(find.byType(ProgressDialog), findsNothing);
  });

  testWidgets('a sync the user asked for still holds the whole app',
      (tester) async {
    await tester.pumpWidget(
      wrap(SyncInProgress(trigger: SyncTrigger.userInitiated)),
    );
    await tester.pump();

    expect(find.byType(SyncScrim), findsOneWidget);
    expect(find.byType(ProgressDialog), findsOneWidget);

    // Dispose the tree while the modal's own periodic timers are still ours.
    await tester.pumpWidget(const SizedBox());
  });

  SyncCompleteWithErrors failed({
    SyncTrigger trigger = SyncTrigger.userInitiated,
  }) =>
      SyncCompleteWithErrors(
        failedDrives: 1,
        totalDrives: 3,
        failedDriveIds: const ['drive-id'],
        errorMessages: const {'drive-id': 'the gateway said no'},
        trigger: trigger,
      );

  testWidgets('a failure the user waited for keeps its modal', (tester) async {
    // They are looking at the sync; the answer belongs where the question was
    // asked, retry and all.
    await tester.pumpWidget(wrap(failed()));
    await tester.pump();

    expect(find.byType(SyncScrim), findsOneWidget);
    expect(find.text('Retry Failed'), findsOneWidget);
  });

  testWidgets('a failure nobody asked for does not take the screen',
      (tester) async {
    // The login sync paints nothing while it runs, so the user is in the
    // middle of something else. One drive out of several failing used to drop
    // a full-screen scrim and "Sync Incomplete - Errors Detected" over it -
    // SyncCompleteWithErrors was the only terminal state with no trigger to
    // honour. It reports at the top bar's sync button instead.
    await tester.pumpWidget(wrap(failed(trigger: SyncTrigger.background)));
    await tester.pump();

    expect(find.byType(SyncScrim), findsNothing);
    expect(find.byType(ArDriveStandardModalNew), findsNothing);
    expect(find.text('Sync Incomplete - Errors Detected'), findsNothing);
  });

  testWidgets('every terminal state follows the sync it came from',
      (tester) async {
    for (final trigger in SyncTrigger.values) {
      expect(
        SyncOverlay.blocksTheApp(failed(trigger: trigger)),
        trigger == SyncTrigger.userInitiated,
        reason: 'a $trigger sync that failed must block exactly as much as a '
            '$trigger sync that is running',
      );
    }
  });

  testWidgets('cancelling follows the sync it came from', (tester) async {
    await tester.pumpWidget(
      wrap(
        SyncCancelled(
          drivesCompleted: 1,
          totalDrives: 3,
          cancelledAt: DateTime.now(),
          trigger: SyncTrigger.background,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SyncScrim), findsNothing);

    await tester.pumpWidget(
      wrap(
        SyncCancelled(
          drivesCompleted: 1,
          totalDrives: 3,
          cancelledAt: DateTime.now(),
          trigger: SyncTrigger.userInitiated,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SyncScrim), findsOneWidget);
  });

  testWidgets('loading drive metadata paints nothing over the app',
      (tester) async {
    // The cubit's initial state, and the metadata-only login path: two more
    // syncs nobody asked for, over a drives list the local database already
    // has.
    await tester.pumpWidget(wrap(SyncLoadingDrives()));
    await tester.pump();

    expect(find.byType(SyncScrim), findsNothing);
    expect(find.byType(ProgressDialog), findsNothing);
  });

  testWidgets('a finished sync never holds the app', (tester) async {
    // Whoever asked for it. The summary is drawn without a scrim and leaves on
    // its own, so a sync that used to end in silence never starts costing a
    // click to get rid of.
    for (final trigger in SyncTrigger.values) {
      expect(
        SyncOverlay.blocksTheApp(
          SyncComplete(
            entitiesSynced: 0,
            completedAt: DateTime.now(),
            sequence: 1,
            trigger: trigger,
          ),
        ),
        isFalse,
        reason: 'a $trigger sync that finished must not block the app',
      );
    }
  });

  testWidgets('the modal the user waited on ends on what the sync found',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        SyncComplete(
          entitiesSynced: 0,
          completedAt: DateTime.now(),
          sequence: 1,
          trigger: SyncTrigger.userInitiated,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Sync Complete'), findsOneWidget);
    expect(find.text('Up to date — nothing new'), findsOneWidget);
    // The wait is over, so the app underneath is free again.
    expect(find.byType(SyncScrim), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the summary sees itself out', (tester) async {
    await tester.pumpWidget(
      wrap(
        SyncComplete(
          entitiesSynced: 12,
          completedAt: DateTime.now(),
          sequence: 1,
          trigger: SyncTrigger.userInitiated,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('12 items changed'), findsOneWidget);

    // Nobody clicks anything here: the modal is gone a few seconds later.
    await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

    expect(find.text('12 items changed'), findsNothing);
    expect(find.byType(ArDriveStandardModalNew), findsNothing);
  });

  testWidgets('a finished background sync is not painted over the app',
      (tester) async {
    // It reports at the top bar's indicator, where it was running - the app
    // was never interrupted for it and must not be interrupted by its result.
    await tester.pumpWidget(
      wrap(
        SyncComplete(
          entitiesSynced: 12,
          completedAt: DateTime.now(),
          sequence: 1,
          trigger: SyncTrigger.background,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SyncScrim), findsNothing);
    expect(find.byType(ArDriveStandardModalNew), findsNothing);
    expect(find.text('12 items changed'), findsNothing);
  });

  testWidgets('a result from an hour ago is not announced again',
      (tester) async {
    // SyncComplete is still the cubit's state long after the sync. The shell
    // builds this stack separately in its desktop and mobile branches, so
    // crossing the breakpoint builds a fresh one - which used to pop a "Sync
    // Complete" modal for a sync that finished an hour earlier.
    await tester.pumpWidget(
      wrap(
        SyncComplete(
          entitiesSynced: 12,
          completedAt: DateTime.now().subtract(const Duration(hours: 1)),
          sequence: 1,
          trigger: SyncTrigger.userInitiated,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Sync Complete'), findsNothing);
    expect(find.text('12 items changed'), findsNothing);
  });

  testWidgets('the modal counts whole percent', (tester) async {
    when(() => syncCubit.syncProgress).thenReturn(
      SyncProgress.initial().copyWith(progress: 0.42),
    );

    await tester.pumpWidget(
      wrap(SyncInProgress(trigger: SyncTrigger.userInitiated)),
    );
    await tester.pump();

    expect(find.text('42% complete'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
