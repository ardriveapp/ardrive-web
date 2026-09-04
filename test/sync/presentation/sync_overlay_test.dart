import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/progress_dialog.dart';
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

  testWidgets('errors block even when nobody asked for the sync',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        SyncCompleteWithErrors(
          failedDrives: 1,
          totalDrives: 3,
          failedDriveIds: const ['drive-id'],
          errorMessages: const {'drive-id': 'the gateway said no'},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SyncScrim), findsOneWidget);
    expect(find.text('Retry Failed'), findsOneWidget);
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
