import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/progress_dialog.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/presentation/sync_overlay.dart';
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

  group('nothing a sync does holds the app any more', () {
    // The modal a user-initiated sync used to hold was a title, a phase line,
    // a bar and a percentage - what SyncStrip carries, under the app bar, on
    // both breakpoints - with no action of its own. What was left of it was a
    // scrim over a copy of what was already on screen.
    for (final trigger in SyncTrigger.values) {
      testWidgets('a $trigger sync that is running paints nothing over the app',
          (tester) async {
        await tester.pumpWidget(wrap(SyncInProgress(trigger: trigger)));
        await tester.pump();

        expect(find.byType(ProgressDialog), findsNothing);
        expect(find.byType(ArDriveStandardModalNew), findsNothing);
        expect(find.text('Cancel'), findsNothing);
      });

      testWidgets('a $trigger sync that failed paints nothing over the app',
          (tester) async {
        // It reports at the top bar, where the indicator was already turning -
        // for both triggers now, since the modal that used to carry the
        // user-initiated one is gone.
        await tester.pumpWidget(wrap(failed(trigger: trigger)));
        await tester.pump();

        expect(find.byType(ArDriveStandardModalNew), findsNothing);
        expect(find.text('Sync Incomplete - Errors Detected'), findsNothing);
        expect(find.text('Retry Failed'), findsNothing);
      });

      testWidgets(
          'a $trigger sync that was cancelled paints nothing over '
          'the app', (tester) async {
        await tester.pumpWidget(
          wrap(
            SyncCancelled(
              drivesCompleted: 1,
              totalDrives: 3,
              cancelledAt: DateTime.now(),
              trigger: trigger,
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ArDriveStandardModalNew), findsNothing);
        expect(find.text('Sync Cancelled'), findsNothing);
      });
    }

    testWidgets('loading drive metadata paints nothing over the app',
        (tester) async {
      await tester.pumpWidget(wrap(SyncLoadingDrives()));
      await tester.pump();

      expect(find.byType(ProgressDialog), findsNothing);
      expect(find.byType(ArDriveStandardModalNew), findsNothing);
    });
  });

  testWidgets('a sync the user asked for is not painted over the app either',
      (tester) async {
    // It used to be: a result the user pressed for got a card in the middle of
    // the screen - full width on a phone, over the page they were reading -
    // while the same result from a background sync got a small pill anchored
    // under the control that had been turning. Two designs for one sentence,
    // with the trigger choosing between them, and failures never split that
    // way at all. Every outcome reports at the indicator now.
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

    expect(find.text('Sync Complete'), findsNothing);
    expect(find.text('12 items changed'), findsNothing);
    expect(find.byType(ArDriveStandardModalNew), findsNothing);

    await tester.pumpWidget(const SizedBox());
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

  group('the gateway a debug build is talking to', () {
    // The only reason this widget draws anything at all while a sync runs. It
    // used to hang off the blocking modal, so removing that would have taken a
    // dev affordance with it - and handing it every sync instead would leave
    // it sitting at the bottom of the window for the whole of every login in
    // dev and staging, which is every session.
    setUp(() {
      when(() => configService.flavor).thenReturn(Flavor.development);
      when(() => configService.config).thenReturn(
        AppConfig(
          allowedDataItemSizeForTurbo: 0,
          stripePublishableKey: '',
          arweaveGatewayForDataRequest: const SelectedGateway(
            label: 'test gateway',
            url: 'https://example.test',
          ),
        ),
      );
    });

    testWidgets('is named for a sync the user asked for', (tester) async {
      await tester.pumpWidget(
        wrap(SyncInProgress(trigger: SyncTrigger.userInitiated)),
      );
      await tester.pump();

      expect(
        find.text('Using gateway: https://example.test'),
        findsOneWidget,
      );
    });

    testWidgets('stays out of the way of a sync nobody asked for',
        (tester) async {
      // As far as the modal it hung off ever reached. The sync on login is a
      // background sync, and it runs on every session.
      await tester.pumpWidget(
        wrap(SyncInProgress(trigger: SyncTrigger.background)),
      );
      await tester.pump();

      expect(find.textContaining('Using gateway:'), findsNothing);
    });

    testWidgets('and never appears in production', (tester) async {
      when(() => configService.flavor).thenReturn(Flavor.production);

      await tester.pumpWidget(
        wrap(SyncInProgress(trigger: SyncTrigger.userInitiated)),
      );
      await tester.pump();

      expect(find.textContaining('Using gateway:'), findsNothing);
    });
  });
}
