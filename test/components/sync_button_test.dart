import 'dart:async';

import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/app_top_bar.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/presentation/sync_summary.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
    when(() => syncCubit.syncStartTime).thenReturn(clock.now());
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
    when(() => syncCubit.retryFailure()).thenAnswer((_) async {});
    when(() => syncCubit.dismissSyncResult()).thenReturn(null);
  });

  tearDown(() async {
    await stateController.close();
    await progressController.close();
  });

  Widget host(
    Widget body, {
    ArDriveThemeData? theme,
    DrivesListCubit? drivesList,
  }) {
    return Portal(
      child: ArDriveTheme(
        themeData: theme ?? lightTheme(),
        // Above the navigator, where the app provides them: a menu opens in
        // the navigator's overlay and reads them from there.
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SyncCubit>.value(value: syncCubit),
            BlocProvider<DrivesCubit>.value(value: drivesCubit),
            // The drives list route provides this above the shell; no other
            // route does.
            if (drivesList != null)
              BlocProvider<DrivesListCubit>.value(value: drivesList),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en', '')],
            home: Scaffold(body: body),
          ),
        ),
      ),
    );
  }

  Widget wrap({ArDriveThemeData? theme, DrivesListCubit? drivesList}) => host(
        const Row(children: [SyncButton()]),
        theme: theme,
        drivesList: drivesList,
      );

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
    // The overlay shows what changed on the frame after.
    await tester.pump();

    if (reporting != null) {
      progressController.add(reporting);
      await tester.pump(const Duration(milliseconds: 10));
      // The overlay shows what changed on the frame after.
      await tester.pump();
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
        completedAt: completedAt ?? clock.now(),
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
    // The overlay shows what changed on the frame after.
    await tester.pump();

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
    // The overlay shows what changed on the frame after.
    await tester.pump();
    expect(ring().value, 0.97);

    // The gateway phase cannot know its own length, so the ring stops
    // claiming a fraction and sweeps instead of sitting at 97%.
    progressController.add(SyncProgress.initial().copyWith(
      progress: 0.97,
      isIndeterminate: true,
      statusMessage: 'Updating transaction statuses...',
    ));
    await tester.pump(const Duration(milliseconds: 10));
    // The overlay shows what changed on the frame after.
    await tester.pump();

    expect(ring().value, isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a ring with nothing to measure turns', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    // No figure yet: turning is what says the sync is working.
    await startSyncing(tester);

    double turns() => tester
        .widget<RotationTransition>(find.byKey(syncIndicatorMotionKey))
        .turns
        .value;

    final before = turns();
    await tester.pump(const Duration(milliseconds: 500));

    expect(turns(), isNot(before));
  });

  testWidgets('a ring that shows progress holds still, so it can be read',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    // A ring that turns while it fills cannot be read: how full it is moves
    // round the circle with it.
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

    expect(turns(), before);
    expect(before, 0, reason: 'upright, with the fill starting at the top');

    // And it turns again once the phase cannot measure itself.
    progressController.add(SyncProgress.initial().copyWith(
      progress: 0.5,
      isIndeterminate: true,
    ));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    final again = turns();
    await tester.pump(const Duration(milliseconds: 500));
    expect(turns(), isNot(again));
  });

  // On the HTML renderer, which phones get, a repaint rebuilds the DOM of
  // everything it covers, so the ring that turns on every frame of a sync
  // repaints alone, and not the top bar around it.
  testWidgets('the turning ring repaints nothing but itself', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();
    // Nothing measured, so the ring turns.
    await startSyncing(tester);

    final glyph = <RenderObject>{};
    void collect(RenderObject o) {
      glyph.add(o);
      o.visitChildren(collect);
    }

    collect(tester.renderObject(find.byType(ArDriveIcon)));
    final painted = <RenderObject>{};
    debugOnProfilePaint = painted.add;
    try {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      debugOnProfilePaint = null;
    }
    expect(
      painted,
      contains(tester.renderObject(find.byKey(syncIndicatorMotionKey))),
      reason: 'the ring turns',
    );
    // The glyph inside the ring stands still, and so does the bar.
    expect(painted.intersection(glyph), isEmpty);
    expect(painted.whereType<RenderParagraph>(), isEmpty);
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
    expect(tooltip.message, contains('Syncing all drives'));
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
    // The overlay shows what changed on the frame after.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getSize(find.byType(SyncButton)), idleSize);
  });

  testWidgets('a finished background sync says what it found', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    await startSyncing(tester);
    stateController.add(finished(entitiesSynced: 12));
    await tester.pump(const Duration(milliseconds: 10));
    // The overlay shows what changed on the frame after.
    await tester.pump();

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
    // The overlay shows what changed on the frame after.
    await tester.pump();

    expect(find.text('Up to date, nothing new'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the result takes itself away', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));
    // The overlay shows what changed on the frame after.
    await tester.pump();

    expect(find.text('Up to date, nothing new'), findsOneWidget);

    await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

    // The overlay lets go of it on the frame after.
    await tester.pump();
    expect(find.text('Up to date, nothing new'), findsNothing);
  });

  testWidgets('the indicator keeps the result after the pill has gone',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(finished(entitiesSynced: 12));
    await tester.pump(const Duration(milliseconds: 10));
    // The overlay shows what changed on the frame after.
    await tester.pump();

    expect(find.byType(ArDriveIcon), findsOneWidget);

    // The pill's few seconds are too short to read (WCAG 2.2.1), so the
    // result stays on the indicator, and in its menu, until the next sync or
    // until it is dismissed.
    await tester.pump(syncSummaryDuration + const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('12 items changed'), findsNothing);
    expect(find.byType(ArDriveIcon), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      '12 items changed',
    );

    await tester.tap(find.byType(SyncButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(
        of: find.byKey(syncStatusHeaderKey),
        matching: find.text('12 items changed'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Dismiss puts the result away', (tester) async {
    when(() => syncCubit.dismissSyncResult()).thenReturn(null);
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(finished(entitiesSynced: 12));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(syncSummaryDuration + const Duration(seconds: 1));
    await tester.pump();

    await tester.tap(find.byType(SyncButton));
    // Until the menu has finished opening and its items take a tap.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.tap(find.text('Dismiss'));
    await tester.pump();

    verify(() => syncCubit.dismissSyncResult()).called(1);

    // The cubit returns to rest, and the slot is empty again.
    stateController.add(SyncIdle());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    expect(find.byType(ArDriveIcon), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the result is told to a screen reader when it shows',
      (tester) async {
    final spoken = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        final data = (message as Map)['data'] as Map;
        if (message['type'] == 'announce') {
          spoken.add(data['message'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility, null));

    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(finished(entitiesSynced: 12, skippedEntityCount: 3));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();

    expect(spoken, ['12 items changed. 3 updates could not be read']);

    // Once: a rebuild does not say it again.
    await tester.pump(const Duration(seconds: 1));
    expect(spoken, hasLength(1));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a result with items it could not read is drawn as a warning',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(finished(entitiesSynced: 12, skippedEntityCount: 3));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();

    final warning = tester.widget<ArDriveStatusText>(find.ancestor(
      of: find.text('3 updates could not be read'),
      matching: find.byType(ArDriveStatusText),
    ));
    expect(warning.type, ArDriveStatusType.warning);

    // And the indicator says so after the pill: the warning's triangle.
    await tester.pump(syncSummaryDuration + const Duration(seconds: 1));
    await tester.pump();
    final glyph = tester.widget<ArDriveIcon>(find.byType(ArDriveIcon));
    expect(glyph.icon, ArDriveIcons.triangle().icon);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a second result that reads the same is shown again',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));
    // The overlay shows what changed on the frame after.
    await tester.pump();
    await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

    // The overlay lets go of it on the frame after.
    await tester.pump();
    expect(find.text('Up to date, nothing new'), findsNothing);

    // Two zero-change syncs read identically, and land in the same
    // millisecond when nothing does any I/O between them. The second one is
    // still a result, and reporting the first must not have used the summary
    // up - so they are told apart by sequence, not by a timestamp.
    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));
    // The overlay shows what changed on the frame after.
    await tester.pump();

    expect(find.text('Up to date, nothing new'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('results never stack up', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));
    // The overlay shows what changed on the frame after.
    await tester.pump();
    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));
    // The overlay shows what changed on the frame after.
    await tester.pump();

    expect(find.text('Up to date, nothing new'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reporting a result does not move the top bar', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    final idleSize = tester.getSize(find.byType(SyncButton));

    stateController.add(finished(entitiesSynced: 12));
    await tester.pump(const Duration(milliseconds: 10));
    // The overlay shows what changed on the frame after.
    await tester.pump();

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
    // The overlay shows what changed on the frame after.
    await tester.pump();

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
      completedAt: clock.now().subtract(const Duration(hours: 1)),
    ));
    await tester.pump(const Duration(milliseconds: 10));
    // The overlay shows what changed on the frame after.
    await tester.pump();

    expect(find.text('12 items changed'), findsNothing);
    // Not flashed again, but still on the indicator: it is the last result,
    // and it stays readable until the next sync or until it is dismissed.
    expect(find.byType(ArDriveIcon), findsOneWidget);
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
    // The overlay shows what changed on the frame after.
    await tester.pump();

    expect(find.text('12 items changed'), findsOneWidget);

    // And it sees itself out, like every other announcement here.
    await tester.pump(syncSummaryDuration + const Duration(seconds: 1));
    // The overlay lets go of it on the frame after.
    await tester.pump();
    expect(find.text('12 items changed'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the summary is drawn in the theme it lands in', (tester) async {
    Future<Color> pillColourUnder(ArDriveThemeData theme) async {
      await tester.pumpWidget(wrap(theme: theme));
      await tester.pump();

      stateController.add(finished());
      await tester.pump(const Duration(milliseconds: 10));
      // The overlay shows what changed on the frame after.
      await tester.pump();

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

    // The raised surface: it floats over the page, as a menu does.
    expect(light, lightTheme().colorTokens.containerRaised);
    expect(dark, ArDriveColorTokens.darkMode().containerRaised);
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
    // The menu enters the navigator's overlay on the frame after the tap.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Opens the menu far enough for an item to take a tap: it reveals through
  /// an offstage transition, and the ring never lets the tree settle.
  Future<void> openMenuToTap(WidgetTester tester) async {
    await tester.tap(find.byType(SyncButton));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
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
      // The overlay shows what changed on the frame after.
      await tester.pump();

      // Beside the indicator that was turning for it - the same surface a
      // successful background sync reports at, and clearly not a success.
      expect(find.text('Sync incomplete: errors detected'), findsOneWidget);
      expect(find.text('2 of 5 drives could not be synced'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('is drawn as a failure, not as a result', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(failed());
      await tester.pump(const Duration(milliseconds: 10));
      // The overlay shows what changed on the frame after.
      await tester.pump();

      final colorTokens = lightTheme().colorTokens;

      final pill = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Sync incomplete: errors detected'),
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
      // The overlay shows what changed on the frame after.
      await tester.pump();
      await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

      // The overlay lets go of it on the frame after.
      await tester.pump();
      expect(find.text('Sync incomplete: errors detected'), findsNothing,
          reason: 'precondition: the announcement has had its few seconds');

      await openMenuToTap(tester);

      // The way to run it again is where the failure is reported, and it
      // runs again exactly the drives that failed - the drives list's own
      // retry, through the same two calls.
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Your drives'), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.pump();

      verify(() => syncCubit.clearErrorState()).called(1);
      verify(() => syncCubit.retryFailedDrives(['drive-a', 'drive-b']))
          .called(1);
      verifyNever(() => syncCubit.syncMetadataOnly());

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
      // The overlay shows what changed on the frame after.
      await tester.pump();

      expect(find.text('Sync incomplete: errors detected'), findsOneWidget);
      expect(find.text('2 of 5 drives could not be synced'), findsOneWidget);

      await openMenu(tester);
      expect(find.text('Try again'), findsOneWidget);

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

      stateController.add(SyncFailure(
        error: Exception('the gateway said no'),
        wasDriveListRefresh: true,
      ));
      await tester.pump(const Duration(milliseconds: 10));
      // The overlay shows what changed on the frame after.
      await tester.pump();

      expect(find.text("Couldn't check for new drives"), findsOneWidget);
      // The drives are listed, so it says what failed - the check for new
      // ones - rather than that the drives could not be loaded.
      expect(
          find.text('The drives shown are from this device.'), findsOneWidget);
      expect(find.text('Drives could not be loaded'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('stays reachable after the announcement has gone',
        (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(SyncFailure(
        error: Exception('the gateway said no'),
        wasDriveListRefresh: true,
      ));
      await tester.pump(const Duration(milliseconds: 10));
      // The overlay shows what changed on the frame after.
      await tester.pump();
      await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

      // The overlay lets go of it on the frame after.
      await tester.pump();
      expect(find.text("Couldn't check for new drives"), findsNothing,
          reason: 'precondition: the announcement has had its few seconds');

      // The failure outlives it, in the surface a partial failure uses: the
      // menu the indicator opens, and the indicator's own red triangle.
      await openMenu(tester);

      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Your drives'), findsNothing);
      // A drive list that could not be read stays reported: the drives page
      // reads this state to avoid saying the account has no drives.
      expect(find.text('Dismiss'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Try again runs the drive-list refresh again, and only that',
        (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(SyncFailure(
        error: Exception('the gateway said no'),
        wasDriveListRefresh: true,
      ));
      await tester.pump(const Duration(milliseconds: 10));
      // The overlay shows what changed on the frame after.
      await tester.pump();

      await openMenuToTap(tester);
      await tester.tap(find.text('Try again'));
      await tester.pump();

      // The request that failed, through the cubit, which knows it was the
      // drive-list refresh: no drive is walked, and no cancelled wallet prompt
      // is asked again.
      verify(() => syncCubit.retryFailure()).called(1);
      verifyNever(() => syncCubit.retryFailedDrives(any()));
      verifyNever(() => syncCubit.clearErrorState());

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        "Try again goes through the drives list's own retry when it is the "
        'page saying so', (tester) async {
      // Its retry holds the page on "still looking" for the length of the
      // request. A refresh it did not start would flash Getting Started over
      // an empty table.
      final drivesList = _MockDrivesListCubit();
      whenListen(
        drivesList,
        const Stream<DrivesListState>.empty(),
        initialState: DrivesListUnavailable(),
      );
      when(() => drivesList.retryLoadingDrives()).thenAnswer((_) async {});

      await tester.pumpWidget(wrap(drivesList: drivesList));
      await tester.pump();

      stateController.add(SyncFailure(
        error: Exception('the gateway said no'),
        wasDriveListRefresh: true,
      ));
      await tester.pump(const Duration(milliseconds: 10));
      // The overlay shows what changed on the frame after.
      await tester.pump();

      await openMenuToTap(tester);
      await tester.tap(find.text('Try again'));
      await tester.pump();

      verify(() => drivesList.retryLoadingDrives()).called(1);
      verifyNever(() => syncCubit.syncMetadataOnly());
      verifyNever(() => syncCubit.retryFailure());

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a retry that succeeds clears it', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(SyncFailure(
        error: Exception('the gateway said no'),
        wasDriveListRefresh: true,
      ));
      await tester.pump(const Duration(milliseconds: 10));
      // The overlay shows what changed on the frame after.
      await tester.pump();
      expect(find.text("Couldn't check for new drives"), findsOneWidget,
          reason: 'precondition: the failure is on screen');

      // The retry runs and this time the drive list arrives.
      stateController.add(SyncLoadingDrives());
      await tester.pump(const Duration(milliseconds: 10));
      // The overlay shows what changed on the frame after.
      await tester.pump();
      stateController.add(SyncIdle());
      await tester.pump(const Duration(milliseconds: 10));
      // The overlay shows what changed on the frame after.
      await tester.pump();

      expect(find.text("Couldn't check for new drives"), findsNothing);
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
        wasDriveListRefresh: true,
        failedAt: clock.now().subtract(const Duration(minutes: 5)),
      ));
      await tester.pump(const Duration(milliseconds: 10));
      // The overlay shows what changed on the frame after.
      await tester.pump();

      // Gone from the announcement, still in the menu: the indicator is what
      // carries a failure that is no longer news.
      expect(
          find.text(
              'The network could not be reached to read your drive list.'),
          findsNothing);

      await openMenu(tester);
      expect(find.text('Try again'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a sync that stopped with an error is not a load failure',
        (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(SyncFailure(
        error: Exception('a parse error'),
        kind: SyncFailureKind.sync,
        singleDriveId: 'drive-a',
      ));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(find.text('Sync stopped with an error'), findsOneWidget);
      expect(find.text('Family Photos was not fully synced.'), findsOneWidget);
      expect(find.text('Drives could not be loaded'), findsNothing);

      await tester.pump(syncSummaryDuration + const Duration(seconds: 1));
      await tester.pump();
      await openMenuToTap(tester);
      // It can be put away, and Try again repeats that sync.
      expect(find.text('Dismiss'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      verify(() => syncCubit.retryFailure()).called(1);

      await tester.pumpWidget(const SizedBox());
    });
  });

  /// What the menu carries: the status, and only what acts on it. Your
  /// drives went: the sidebar is always the way there.
  group('the menu', () {
    /// The labels of the menu's actions, top to bottom.
    List<String> actions(WidgetTester tester) => tester
        .widgetList<ArDriveDropdownItemTile>(
            find.byType(ArDriveDropdownItemTile))
        .map((tile) => tile.name)
        .toList();

    Future<void> enter(WidgetTester tester, SyncState state) async {
      stateController.add(state);
      await tester.pump(const Duration(milliseconds: 10));
      // The overlay shows what changed on the frame after.
      await tester.pump();
    }

    testWidgets('while a sync runs it offers Stop syncing alone',
        (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      await startSyncing(tester);
      await openMenu(tester);

      expect(actions(tester), ['Stop syncing']);
    });

    // Some drives failing is a result, so it can be put away; a drive list
    // that could not be read stays reported, because the drives page reads
    // it to avoid saying the account has no drives.
    for (final (name, state, expected) in [
      ('some drives', () => failed(), ['Try again', 'Dismiss']),
      (
        'the drive list',
        () => SyncFailure(error: Exception('no')),
        ['Try again'],
      ),
    ]) {
      testWidgets('after $name failed it offers $expected', (tester) async {
        await tester.pumpWidget(wrap());
        await tester.pump();
        await enter(tester, state());
        await openMenu(tester);

        expect(actions(tester), expected);

        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('Your drives is in no state', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      final states = <String, SyncState Function()>{
        'running': () => SyncInProgress(trigger: SyncTrigger.background),
        'loading the drive list': () => SyncLoadingDrives(),
        'some drives failed': () => failed(),
        'the drive list failed': () => SyncFailure(error: Exception('no')),
        'the wallet changed': () => SyncWalletMismatch(),
        'cancelled': () => SyncCancelled(
              drivesCompleted: 1,
              totalDrives: 3,
              cancelledAt: clock.now(),
            ),
      };

      for (final MapEntry(key: name, value: state) in states.entries) {
        await enter(tester, state());
        await openMenu(tester);

        expect(find.byKey(syncStatusHeaderKey), findsOneWidget, reason: name);
        expect(find.text('Your drives'), findsNothing, reason: name);

        // Closed again by a tap on the barrier, away from the menu.
        await tester.tapAt(const Offset(5, 500));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a state with nothing to act on opens the status alone',
        (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      await enter(tester, SyncLoadingDrives());
      await openMenu(tester);

      expect(find.byKey(syncStatusHeaderKey), findsOneWidget);
      expect(find.text('Loading your drives...'), findsOneWidget);
      expect(actions(tester), isEmpty);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a result opens its status and a way to put it away',
        (tester) async {
      // It used to have only its pill to show, so a tap opened nothing. The
      // result is now read here once the pill has gone.
      await tester.pumpWidget(wrap());
      await tester.pump();
      await enter(tester, finished(entitiesSynced: 3));
      await openMenu(tester);

      expect(
        find.descendant(
          of: find.byKey(syncStatusHeaderKey),
          matching: find.text('3 items changed'),
        ),
        findsOneWidget,
      );
      expect(actions(tester), ['Dismiss']);

      await tester.pumpWidget(const SizedBox());
    });

    for (final (name, theme) in [
      ('light', lightTheme()),
      ('dark', ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode())),
    ]) {
      testWidgets('Try again is drawn as Stop syncing is, $name',
          (tester) async {
        // One menu item, ardrive_ui's: the same tile, an icon of the same
        // size in the same token, and the icon and label at the same insets.
        Finder tileOf(String item) => find.ancestor(
              of: find.text(item),
              matching: find.byType(ArDriveDropdownItemTile),
            );
        Finder iconOf(String item) => find.descendant(
              of: tileOf(item),
              matching: find.byType(ArDriveIcon),
            );

        ({ArDriveIcon icon, Size size, double iconInset, double labelInset})
            measure(String item) {
          final tileLeft = tester.getTopLeft(tileOf(item)).dx;
          return (
            icon: tester.widget<ArDriveIcon>(iconOf(item)),
            size: tester.getSize(iconOf(item)),
            iconInset: tester.getTopLeft(iconOf(item)).dx - tileLeft,
            labelInset: tester.getTopLeft(find.text(item)).dx - tileLeft,
          );
        }

        await tester.pumpWidget(wrap(theme: theme));
        await tester.pump();

        await startSyncing(tester);
        await openMenu(tester);
        final stop = measure('Stop syncing');

        await tester.tapAt(const Offset(5, 500));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await enter(tester, failed());
        await openMenu(tester);
        final tryAgain = measure('Try again');

        expect(tryAgain.icon.icon, ArDriveIcons.refresh().icon);
        expect(tryAgain.icon.color, theme.colorTokens.textHigh);
        expect(tryAgain.icon.color, stop.icon.color);
        expect(tryAgain.size, stop.size);
        expect(tryAgain.iconInset, stop.iconInset);
        expect(tryAgain.labelInset, stop.labelInset);
        expect(
          tester.widget<Text>(find.text('Try again')).style?.color,
          theme.colorTokens.textHigh,
        );

        await tester.pumpWidget(const SizedBox());
      });
    }
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
      // The overlay shows what changed on the frame after.
      await tester.pump();

      expect(find.text('Wallet changed'), findsOneWidget);
      expect(
        find.text('You were signed out because your wallet changed.'),
        findsOneWidget,
      );

      // And it outlives the announcement, on the indicator itself, like every
      // other way a sync can end badly.
      await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, contains('Wallet changed'));
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
      // The overlay shows what changed on the frame after.
      await tester.pump();

      final colorTokens =
          ArDriveTheme.of(tester.element(find.byType(SyncButton)))
              .themeData
              .colorTokens;

      // ardrive_ui's error status text: red, with the error icon.
      expect(
        tester.widget<Text>(find.text('Wallet changed')).style?.color,
        colorTokens.statusErrorFg,
      );
      expect(
        find.ancestor(
          of: find.text('Wallet changed'),
          matching: find.byType(ArDriveStatusText),
        ),
        findsOneWidget,
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
          cancelledAt: clock.now(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));
      // The overlay shows what changed on the frame after.
      await tester.pump();

      // "Stopped", the word on the button that stops it and on the drives it
      // did not finish.
      expect(find.text('Sync stopped'), findsOneWidget);
      expect(find.text('Completed 1 of 3 drives'), findsOneWidget);

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, contains('Sync stopped'));
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
          cancelledAt: clock.now(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));
      // The overlay shows what changed on the frame after.
      await tester.pump();

      verifyNever(() => syncCubit.clearCancelledState());

      await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

      verify(() => syncCubit.clearCancelledState()).called(1);
      // The overlay lets go of it on the frame after.
      await tester.pump();
      expect(find.text('Sync stopped'), findsNothing);

      // The cubit moves on to rest, and the indicator still says the sync was
      // stopped, in its tooltip and menu, until the next one.
      stateController.add(SyncStopped(
        drivesCompleted: 1,
        totalDrives: 3,
        stoppedAt: clock.now(),
      ));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        'Sync stopped\nCompleted 1 of 3 drives',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('one drive is singular', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(SyncCancelled(
        drivesCompleted: 0,
        totalDrives: 1,
        cancelledAt: clock.now(),
      ));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();

      expect(find.text('Completed 0 of 1 drive'), findsOneWidget);

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

class _MockDrivesListCubit extends MockCubit<DrivesListState>
    implements DrivesListCubit {}
