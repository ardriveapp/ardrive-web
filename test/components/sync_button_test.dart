import 'dart:async';

import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/app_top_bar.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/presentation/sync_summary.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

void main() {
  // The running indicator's ring never settles, so every pump here elapses a
  // beat rather than calling pumpAndSettle - which would spin forever.
  late MockSyncBloc syncCubit;
  late MockDrivesCubit drivesCubit;
  late StreamController<SyncState> stateController;
  late StreamController<SyncProgress> progressController;

  setUp(() {
    syncCubit = MockSyncBloc();
    drivesCubit = MockDrivesCubit();
    // Broadcast on purpose: a single-subscription controller with nobody
    // listening never completes its close(), so a SyncButton unwired from the
    // cubit would hang this file's tearDown instead of failing a test.
    stateController = StreamController<SyncState>.broadcast();
    progressController = StreamController<SyncProgress>.broadcast();

    whenListen(
      syncCubit,
      stateController.stream,
      initialState: SyncIdle(),
    );
    // The top bar reads the drive list for one string: the name of the drive a
    // single-drive sync is walking.
    whenListen(
      drivesCubit,
      const Stream<DrivesState>.empty(),
      initialState: DrivesLoadSuccess(
        selectedDriveId: null,
        userDrives: [_drive(id: 'drive-a', name: 'Family Photos')],
        sharedDrives: [_drive(id: 'drive-b', name: 'Shared Reports')],
        drivesWithAlerts: const [],
        canCreateNewDrive: true,
      ),
    );
    when(() => syncCubit.syncProgressController).thenReturn(progressController);
    when(() => syncCubit.syncProgress).thenReturn(SyncProgress.initial());
    when(() => syncCubit.syncStartTime).thenReturn(DateTime.now());
    // Null is "no single-drive sync is running", which is every case but the
    // ones that say otherwise.
    when(() => syncCubit.syncingDriveId).thenReturn(null);
    // The run's own scope and what it has finished, read by every surface
    // that tells a drive in the run from one beside it. Null scope is
    // "every drive"; nothing finished yet.
    when(() => syncCubit.syncingDriveIds).thenReturn(null);
    when(() => syncCubit.completedDriveIds).thenReturn(const []);
    when(() => syncCubit.clearErrorState()).thenReturn(null);
    when(() => syncCubit.retryFailedDrives(any())).thenAnswer((_) async {});
    when(() => syncCubit.syncMetadataOnly()).thenAnswer((_) async {});
    when(() => syncCubit.clearCancelledState()).thenReturn(null);
  });

  tearDown(() async {
    await stateController.close();
    await progressController.close();
  });

  Widget host(Widget body, {ArDriveThemeData? theme}) {
    return Portal(
      child: ArDriveTheme(
        themeData: theme ?? lightTheme(),
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
                BlocProvider<DrivesCubit>.value(value: drivesCubit),
              ],
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  Widget wrap({ArDriveThemeData? theme}) =>
      host(const Row(children: [SyncButton()]), theme: theme);

  /// The button as `MobileAppBar` places it: against the trailing edge, with
  /// the rest of the bar's chrome to its right.
  Widget wrapNarrow({required double trailingChrome}) => host(
        Align(
          alignment: Alignment.topRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SyncButton(),
              SizedBox(width: trailingChrome),
            ],
          ),
        ),
      );

  /// Puts a running sync on screen, with whatever it is reporting.
  Future<void> startSyncing(
    WidgetTester tester, {
    SyncProgress? reporting,
  }) async {
    stateController.add(SyncInProgress(trigger: SyncTrigger.background));
    await tester.pump(const Duration(milliseconds: 10));

    if (reporting != null) {
      progressController.add(reporting);
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  /// A finished sync, as the cubit reports it. [sequence] is what tells two
  /// results apart - see [SyncComplete.sequence] - so each call gets its own.
  var nextSequence = 0;
  SyncComplete finished({
    int entitiesSynced = 0,
    int skippedEntityCount = 0,
    bool isSingleDriveSync = false,
    String? driveName,
    SyncTrigger trigger = SyncTrigger.background,
    DateTime? completedAt,
    int? sequence,
  }) =>
      SyncComplete(
        entitiesSynced: entitiesSynced,
        skippedEntityCount: skippedEntityCount,
        isSingleDriveSync: isSingleDriveSync,
        driveName: driveName,
        trigger: trigger,
        completedAt: completedAt ?? DateTime.now(),
        sequence: sequence ?? ++nextSequence,
      );

  testWidgets('an idle sync shows nothing at all', (tester) async {
    // The indicator is present only when there is something to report. A
    // control that is idle almost always is ambient noise in the one corner
    // that should be quiet, and every other level of this report already
    // follows the rule: say nothing when there is nothing to say. The actions
    // it used to carry live on the drives list - see `DrivesSyncMenu`.
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ArDriveIcon), findsNothing);
  });

  testWidgets('a running sync turns the icon into a progress ring',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    await startSyncing(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // The refresh glyph stays, inside the ring.
    expect(find.byType(ArDriveIcon), findsOneWidget);
  });

  testWidgets('the glyph is drawn in the same token the bar uses',
      (tester) async {
    // There is no idle glyph to compare against any more - the indicator is
    // absent until there is something to report - so the invariant is stated
    // against the token rather than against a previous state: it must not
    // arrive shouting in a colour nothing else in the bar uses.
    await tester.pumpWidget(wrap());
    await tester.pump();

    await startSyncing(tester);

    expect(
      tester.widget<ArDriveIcon>(find.byType(ArDriveIcon)).color,
      lightTheme().colorTokens.textMid,
    );
  });

  testWidgets('the ring fills once the sync reports progress', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    await startSyncing(tester);

    CircularProgressIndicator ring() =>
        tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );

    expect(ring().value, isNull);

    progressController.add(SyncProgress.initial().copyWith(progress: 0.5));
    await tester.pump(const Duration(milliseconds: 10));

    expect(ring().value, 0.5);
  });

  testWidgets('a phase that cannot measure itself empties the ring',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    await startSyncing(tester);

    CircularProgressIndicator ring() =>
        tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );

    progressController.add(SyncProgress.initial().copyWith(progress: 0.97));
    await tester.pump(const Duration(milliseconds: 10));
    expect(ring().value, 0.97);

    // The gateway phase cannot know its own length, so the ring stops
    // claiming a fraction and sweeps instead of sitting at 97%.
    progressController.add(SyncProgress.initial().copyWith(
      progress: 0.97,
      isIndeterminate: true,
      statusMessage: 'Updating transaction statuses...',
    ));
    await tester.pump(const Duration(milliseconds: 10));

    expect(ring().value, isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the ring keeps moving while progress stands still',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    // A determinate arc is the case that can go still: sync progress plateaus
    // for long stretches and a frozen arc reads as a hang.
    await startSyncing(
      tester,
      reporting: SyncProgress.initial().copyWith(progress: 0.5),
    );

    double turns() => tester
        .widget<RotationTransition>(find.byKey(syncIndicatorMotionKey))
        .turns
        .value;

    final before = turns();
    await tester.pump(const Duration(milliseconds: 500));

    expect(turns(), isNot(before));
  });

  testWidgets('hovering the running indicator names the phase', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    await startSyncing(
      tester,
      reporting: SyncProgress.initial().copyWith(
        statusMessage: 'Downloading drive snapshots...',
      ),
    );

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    // The same name the sync modal gives this event, not a third one.
    expect(tooltip.message, contains('Syncing All Drives'));
    expect(tooltip.message, contains('Downloading drive snapshots...'));
  });

  testWidgets('the percentage stands in when the sync names no phase',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    await startSyncing(
      tester,
      reporting: SyncProgress.initial().copyWith(progress: 0.42),
    );

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('42% complete'));
    expect(tooltip.message, isNot(contains('42.0')));
  });

  testWidgets('starting a sync does not move the top bar', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    final idleSize = tester.getSize(find.byType(SyncButton));

    await startSyncing(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(SyncButton)), idleSize);

    stateController.add(SyncIdle());
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getSize(find.byType(SyncButton)), idleSize);
  });

  testWidgets('a finished background sync says what it found', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    await startSyncing(tester);
    stateController.add(finished(entitiesSynced: 12));
    await tester.pump(const Duration(milliseconds: 10));

    // Beside the indicator that was turning for it - no hover, no click.
    expect(find.text('12 items changed'), findsOneWidget);
    // And the sync is over, so the ring is gone.
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a sync that changed nothing still says so', (tester) async {
    // The case the whole summary exists for: told nothing changed, the user
    // learns the next one is safe to ignore.
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Up to date, nothing new'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the result takes itself away', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Up to date, nothing new'), findsOneWidget);

    await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

    expect(find.text('Up to date, nothing new'), findsNothing);
  });

  testWidgets('a second result that reads the same is shown again',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

    expect(find.text('Up to date, nothing new'), findsNothing);

    // Two zero-change syncs read identically, and land in the same
    // millisecond when nothing does any I/O between them. The second one is
    // still a result, and reporting the first must not have used the summary
    // up - so they are told apart by sequence, not by a timestamp.
    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Up to date, nothing new'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('results never stack up', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));
    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Up to date, nothing new'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reporting a result does not move the top bar', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    final idleSize = tester.getSize(find.byType(SyncButton));

    stateController.add(finished(entitiesSynced: 12));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('12 items changed'), findsOneWidget);
    expect(tester.getSize(find.byType(SyncButton)), idleSize);

    // And nothing moves back when it leaves either.
    await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

    expect(tester.getSize(find.byType(SyncButton)), idleSize);
  });

  testWidgets(
      'what could not be read survives a long drive name on a narrow phone',
      (tester) async {
    // The pill is capped at the status header's width and the arrival clause
    // is allowed to ellipsize. Joined into one string the unreadable clause
    // came last, so a long drive name pushed it past the cap and the ellipsis
    // ate the one clause that says this sync has holes in it - inverting the
    // rule the summary exists to state.
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrapNarrow(trailingChrome: 120));
    await tester.pump();

    stateController.add(finished(
      entitiesSynced: 12,
      skippedEntityCount: 3,
      isSingleDriveSync: true,
      driveName: 'Family Photos And Videos Nineteen Ninety Nine To Today',
    ));
    await tester.pump(const Duration(milliseconds: 10));

    const unreadable = '3 updates could not be read';
    expect(find.text(unreadable), findsOneWidget);

    // Rendered, not merely present: the clause has to fit the lines it was
    // given, and start on screen.
    final paragraph =
        tester.renderObject<RenderParagraph>(find.text(unreadable));
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'the unreadable count must never be the part that gets cut',
    );
    expect(
        tester.getTopLeft(find.text(unreadable)).dx, greaterThanOrEqualTo(0));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a result from an hour ago is not flashed again', (tester) async {
    // SyncComplete is still the cubit's state long after the sync. The shell
    // builds the top bar afresh when the layout crosses its breakpoint, which
    // used to pop the summary for a sync that finished an hour earlier.
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(finished(
      entitiesSynced: 12,
      completedAt: DateTime.now().subtract(const Duration(hours: 1)),
    ));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('12 items changed'), findsNothing);
    // And nothing is drawn at all: a result this old is not worth reporting,
    // and there is no sync running to report on.
    expect(find.byType(ArDriveIcon), findsNothing);
  });

  testWidgets('a sync the user asked for reports here too', (tester) async {
    // It used to be left to a card in the middle of the screen while a
    // background sync reported here. Two designs for one sentence, chosen by
    // who asked - and failures never split that way. Every outcome reports at
    // the indicator now, anchored under the control that was turning.
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(
      finished(
        entitiesSynced: 12,
        trigger: SyncTrigger.userInitiated,
      ),
    );
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('12 items changed'), findsOneWidget);

    // And it sees itself out, like every other announcement here.
    await tester.pump(syncSummaryDuration + const Duration(seconds: 1));
    expect(find.text('12 items changed'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the summary is drawn in the theme it lands in', (tester) async {
    Future<Color> pillColourUnder(ArDriveThemeData theme) async {
      await tester.pumpWidget(wrap(theme: theme));
      await tester.pump();

      stateController.add(finished());
      await tester.pump(const Duration(milliseconds: 10));

      final pill = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Up to date, nothing new'),
              matching: find.byType(Container),
            )
            .first,
      );
      await tester.pumpWidget(const SizedBox());

      return (pill.decoration! as BoxDecoration).color!;
    }

    final light = await pillColourUnder(lightTheme());
    final dark = await pillColourUnder(
      ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode()),
    );

    expect(light, lightTheme().colorTokens.containerL1);
    expect(dark, ArDriveColorTokens.darkMode().containerL1);
    // Which is the point: a colour written into the widget would be the same
    // one in both, and unreadable in one of them.
    expect(light, isNot(dark));
  });

  testWidgets('the resync menu survives a running sync', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    // Nothing to open while idle - the indicator is absent until there is
    // something to report.
    expect(find.byType(ArDriveDropdown), findsNothing);

    await startSyncing(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ArDriveDropdown), findsOneWidget);
  });

  /// A sync that ended with drives it could not read, as the cubit reports it.
  SyncCompleteWithErrors failed({
    SyncTrigger trigger = SyncTrigger.background,
    DateTime? completedAt,
  }) =>
      SyncCompleteWithErrors(
        completedAt: completedAt,
        failedDrives: 2,
        totalDrives: 5,
        failedDriveIds: const ['drive-a', 'drive-b'],
        errorMessages: const {'drive-a': 'the gateway said no'},
        trigger: trigger,
      );

  /// Opens the resync menu and waits for it to finish expanding.
  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(SyncButton));
    await tester.pump(const Duration(milliseconds: 300));
  }

  // The groups that tested Resync, Deep Resync, Retry and the record moved with
  // them: those actions now live on the drives list, and
  // `test/drives_list/drives_sync_menu_test.dart` covers them there. What is
  // left here is what this button still does - report, and get out of the way.

  group('a background sync that failed', () {
    testWidgets('says so at the top bar rather than over the app',
        (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      await startSyncing(tester);
      stateController.add(failed());
      await tester.pump(const Duration(milliseconds: 10));

      // Beside the indicator that was turning for it - the same surface a
      // successful background sync reports at, and clearly not a success.
      expect(find.text('Sync Incomplete - Errors Detected'), findsOneWidget);
      expect(find.text('2 of 5 drives could not be synced'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('is drawn as a failure, not as a result', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(failed());
      await tester.pump(const Duration(milliseconds: 10));

      final colorTokens = lightTheme().colorTokens;

      final pill = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Sync Incomplete - Errors Detected'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (pill.decoration! as BoxDecoration).border,
        Border.all(color: colorTokens.strokeRed),
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('leaves retry reachable after the announcement has gone',
        (tester) async {
      // The announcement takes itself away like every other one. The failure
      // does not: the question it asks - retry these drives? - is still open,
      // and the modal that used to ask it is no longer allowed to.
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(failed());
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

      expect(find.text('Sync Incomplete - Errors Detected'), findsNothing,
          reason: 'precondition: the announcement has had its few seconds');

      await openMenu(tester);

      // Retry lives on the drives list now - see
      // `test/drives_list/drives_sync_menu_test.dart`. What this menu owes is
      // the way to the page that carries it.
      expect(find.text('Retry Failed'), findsNothing);
      expect(find.text('All drives'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failure the user asked for reports here too',
        (tester) async {
      // It used to be filtered out, because a user-initiated sync was holding
      // a modal that said the same thing with the same retry. That modal is
      // gone, so this is the only surface left: filtering here now would leave
      // a sync the user pressed a button for reporting its failures nowhere at
      // all.
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(failed(trigger: SyncTrigger.userInitiated));
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Sync Incomplete - Errors Detected'), findsOneWidget);
      expect(find.text('2 of 5 drives could not be synced'), findsOneWidget);

      await openMenu(tester);
      expect(find.text('All drives'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  /// The other way a sync fails: not "some drives could not be read" but "this
  /// could not be done at all". `syncMetadataOnly` is the only place that
  /// emits it terminally - everywhere else `onError` emits it and `SyncIdle`
  /// in the same turn - and it is the whole of a default login, so it is
  /// exactly the failure a user is most likely to hit.
  group('a drive-list refresh that failed', () {
    testWidgets('is visible at the top bar instead of the idle refresh icon',
        (tester) async {
      // The bug: no branch for SyncFailure, so it fell through to the final
      // `else` and drew the ordinary refresh icon. With autoSync false in all
      // three flavours nothing was going to retry it either - so the app
      // looked fully synced while showing nothing, permanently.
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(SyncFailure(error: Exception('the gateway said no')));
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Drives Could Not Be Loaded'), findsOneWidget);
      expect(
          find.text(
              'The network could not be reached to read your drive list.'),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('stays reachable after the announcement has gone',
        (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(SyncFailure(error: Exception('the gateway said no')));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

      expect(find.text('Drives Could Not Be Loaded'), findsNothing,
          reason: 'precondition: the announcement has had its few seconds');

      // The failure outlives it, in the surface a partial failure uses: the
      // menu the indicator opens, and the indicator's own red triangle.
      await openMenu(tester);

      expect(find.text('All drives'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a retry that succeeds clears it', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(SyncFailure(error: Exception('the gateway said no')));
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Drives Could Not Be Loaded'), findsOneWidget,
          reason: 'precondition: the failure is on screen');

      // The retry runs and this time the drive list arrives.
      stateController.add(SyncLoadingDrives());
      await tester.pump(const Duration(milliseconds: 10));
      stateController.add(SyncIdle());
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Drives Could Not Be Loaded'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // And the indicator goes with it: the failure is resolved, nothing is
      // running, so there is nothing to report and nothing to open.
      expect(find.byType(ArDriveDropdown), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failure that has had its moment is not announced again',
        (tester) async {
      // SyncFailure stays the cubit's state until something refreshes the
      // drive list, so an announcement counted from build time would replay on
      // every rebuild of the top bar for the rest of the session.
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(SyncFailure(
        error: Exception('the gateway said no'),
        failedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ));
      await tester.pump(const Duration(milliseconds: 10));

      // Gone from the announcement, still in the menu: the indicator is what
      // carries a failure that is no longer news.
      expect(
          find.text(
              'The network could not be reached to read your drive list.'),
          findsNothing);

      await openMenu(tester);
      expect(find.text('All drives'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  /// The two states the app used to emit and render nowhere at all.
  group('states that had no surface', () {
    testWidgets('a wallet that changed under the sync says so', (tester) async {
      // `arconnectSync` emits SyncWalletMismatch and signs the user out. It
      // was rendered by nothing: the user was bounced to login with no
      // explanation from the layer that noticed.
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(SyncWalletMismatch());
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Wallet Changed'), findsOneWidget);
      expect(
        find.text('You were signed out because your wallet changed.'),
        findsOneWidget,
      );

      // And it outlives the announcement, on the indicator itself, like every
      // other way a sync can end badly.
      await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, contains('Wallet Changed'));
      expect(
        tooltip.message,
        contains('You were signed out because your wallet changed.'),
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a wallet that changed is drawn as a problem', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(SyncWalletMismatch());
      await tester.pump(const Duration(milliseconds: 10));

      final colorTokens =
          ArDriveTheme.of(tester.element(find.byType(SyncButton)))
              .themeData
              .colorTokens;

      expect(
        tester.widget<Text>(find.text('Wallet Changed')).style?.color,
        colorTokens.textRed,
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a cancelled sync says what it got through', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(
        SyncCancelled(
          drivesCompleted: 1,
          totalDrives: 3,
          cancelledAt: DateTime.now(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Sync Cancelled'), findsOneWidget);
      expect(find.text('Completed 1 of 3 drives'), findsOneWidget);

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, contains('Sync Cancelled'));
      expect(tooltip.message, contains('Completed 1 of 3 drives'));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a cancelled sync is let go of once it has been reported',
        (tester) async {
      // The OK button that used to call this lived on the modal, and the modal
      // is gone. Without a replacement the cubit would rest in SyncCancelled
      // for the rest of the session - and two things wait on SyncIdle to do
      // their work: the explorer's refresh and the shared-file handover.
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(
        SyncCancelled(
          drivesCompleted: 1,
          totalDrives: 3,
          cancelledAt: DateTime.now(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));

      verifyNever(() => syncCubit.clearCancelledState());

      await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

      verify(() => syncCubit.clearCancelledState()).called(1);
      expect(find.text('Sync Cancelled'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });
}

/// A drive row as `DrivesCubit` hands them over, with only the two fields the
/// top bar reads filled in with anything meaningful.
Drive _drive({required String id, required String name}) => Drive(
      id: id,
      name: name,
      rootFolderId: 'root-$id',
      ownerAddress: 'owner',
      privacy: 'public',
      isHidden: false,
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
    );
