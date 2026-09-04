import 'dart:async';

import 'package:ardrive/components/app_top_bar.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
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
  late StreamController<SyncState> stateController;
  late StreamController<SyncProgress> progressController;

  setUp(() {
    syncCubit = MockSyncBloc();
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
    when(() => syncCubit.syncProgressController).thenReturn(progressController);
    when(() => syncCubit.syncProgress).thenReturn(SyncProgress.initial());
    when(() => syncCubit.syncStartTime).thenReturn(DateTime.now());
    when(() => syncCubit.clearErrorState()).thenReturn(null);
    when(() => syncCubit.retryFailedDrives(any())).thenAnswer((_) async {});
    when(() => syncCubit.syncMetadataOnly()).thenAnswer((_) async {});
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
            body: BlocProvider<SyncCubit>.value(
              value: syncCubit,
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

  testWidgets('an idle sync leaves the plain refresh icon alone',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ArDriveIcon), findsOneWidget);
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

  testWidgets('the glyph keeps its colour when a sync starts', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    final idle = tester.widget<ArDriveIcon>(find.byType(ArDriveIcon)).color;

    await startSyncing(tester);

    expect(
      tester.widget<ArDriveIcon>(find.byType(ArDriveIcon)).color,
      idle,
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

  testWidgets('tapping the indicator reports the sync without a hover',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    await startSyncing(
      tester,
      reporting: SyncProgress.initial().copyWith(
        progress: 0.42,
        statusMessage: 'Downloading drive snapshots...',
      ),
    );

    // No pointer goes near the button: this is the phone's only way in.
    await tester.tap(find.byType(SyncButton));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Syncing All Drives'), findsOneWidget);
    expect(find.text('Downloading drive snapshots...'), findsOneWidget);
    expect(find.textContaining('s elapsed'), findsOneWidget);
    // And the actions the menu is there for are still under it.
    expect(find.text('Resync'), findsOneWidget);

    // Dispose the tree while the header's own periodic timer is still ours.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the status header stays on screen on a narrow phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrapNarrow(trailingChrome: 120));
    await tester.pump();

    await startSyncing(
      tester,
      reporting: SyncProgress.initial().copyWith(
        progress: 0.42,
        statusMessage: 'Downloading drive snapshots...',
      ),
    );

    await tester.tap(find.byType(SyncButton));
    await tester.pump(const Duration(milliseconds: 300));

    // The menu is wider than the room left of a right-anchored button on a
    // 320px screen, so without the anchor's shift the first characters of both
    // lines sit off the left edge and cannot be read.
    expect(
      tester.getTopLeft(find.text('Syncing All Drives')).dx,
      greaterThanOrEqualTo(0),
    );
    expect(
      tester.getTopLeft(find.text('Downloading drive snapshots...')).dx,
      greaterThanOrEqualTo(0),
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the status header keeps out of an idle menu', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    await tester.tap(find.byType(SyncButton));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Resync'), findsOneWidget);
    expect(find.textContaining('s elapsed'), findsNothing);
    expect(find.text('Syncing All Drives'), findsNothing);

    await tester.pumpWidget(const SizedBox());
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

    expect(find.text('Up to date — nothing new'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the result takes itself away', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Up to date — nothing new'), findsOneWidget);

    await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

    expect(find.text('Up to date — nothing new'), findsNothing);
  });

  testWidgets('a second result that reads the same is shown again',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(syncSummaryDuration + const Duration(seconds: 1));

    expect(find.text('Up to date — nothing new'), findsNothing);

    // Two zero-change syncs read identically, and land in the same
    // millisecond when nothing does any I/O between them. The second one is
    // still a result, and reporting the first must not have used the summary
    // up - so they are told apart by sequence, not by a timestamp.
    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Up to date — nothing new'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('results never stack up', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));
    stateController.add(finished());
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Up to date — nothing new'), findsOneWidget);

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
    // And the button is its idle self, not a flash with nothing in it.
    expect(find.byType(ArDriveIcon), findsOneWidget);
  });

  testWidgets('a sync the user asked for is left to its own modal',
      (tester) async {
    // It has been holding a modal the whole time; the result belongs there,
    // and saying it twice would be twice as much to dismiss.
    await tester.pumpWidget(wrap());
    await tester.pump();

    stateController.add(
      finished(
        entitiesSynced: 12,
        trigger: SyncTrigger.userInitiated,
      ),
    );
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('12 items changed'), findsNothing);
    // The button is back to its idle self.
    expect(find.byType(ArDriveIcon), findsOneWidget);
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
              of: find.text('Up to date — nothing new'),
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

    expect(find.byType(ArDriveDropdown), findsOneWidget);

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

  ArDriveDropdownItemTile itemNamed(WidgetTester tester, String name) =>
      tester.widget<ArDriveDropdownItemTile>(
        find.widgetWithText(ArDriveDropdownItemTile, name),
      );

  /// The menu entry behind an item, so a test can ask whether it has anything
  /// to run. The items live in the portal's overlay, where a synthesised tap
  /// lands on the dropdown's own dismiss barrier rather than on the row, so
  /// what the row would do is read off the item instead of mimed at it.
  ArDriveDropdownItem entryNamed(WidgetTester tester, String name) =>
      tester.widget<ArDriveDropdownItem>(
        find.ancestor(
          of: find.widgetWithText(ArDriveDropdownItemTile, name),
          matching: find.byType(ArDriveDropdownItem),
        ),
      );

  group('the menu while a sync runs', () {
    testWidgets('resync says it is unavailable rather than doing nothing',
        (tester) async {
      // `SyncCubit.startSync` returns immediately while a sync is in progress -
      // a guard written when a running sync scrimmed the app and nobody could
      // ask. Now the menu is fully interactive, so an item that looks normal,
      // closes the menu and drops the request is a lie.
      await tester.pumpWidget(wrap());
      await tester.pump();

      await openMenu(tester);
      expect(itemNamed(tester, 'Resync').isDisabled, isFalse,
          reason: 'precondition: an idle menu offers the actions');
      expect(itemNamed(tester, 'Deep Resync').isDisabled, isFalse);
      expect(entryNamed(tester, 'Resync').onClick, isNotNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(wrap());
      await tester.pump();
      await startSyncing(tester);
      await openMenu(tester);

      expect(itemNamed(tester, 'Resync').isDisabled, isTrue);
      expect(itemNamed(tester, 'Deep Resync').isDisabled, isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a resync that cannot start is never recorded as one',
        (tester) async {
      // The dropped request used to take a Plausible event and a profile-name
      // refresh with it. Both live in the same closure as the startSync call,
      // and a disabled item has no closure at all.
      await tester.pumpWidget(wrap());
      await tester.pump();
      await startSyncing(tester);
      await openMenu(tester);

      // Nothing to run at all, which is what keeps the event out: the
      // Plausible call and the profile-name refresh sat in the same closure as
      // the startSync that would have been dropped.
      expect(entryNamed(tester, 'Resync').onClick, isNull);
      expect(entryNamed(tester, 'Deep Resync').onClick, isNull);

      verifyNever(() => syncCubit.startSync(deepSync: false));
      verifyNever(() => syncCubit.startSync(deepSync: true));

      await tester.pumpWidget(const SizedBox());
    });
  });

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

      expect(find.text('Sync Incomplete - Errors Detected'), findsOneWidget);
      expect(find.text('Retry Failed'), findsOneWidget);

      entryNamed(tester, 'Retry Failed').onClick!();
      await tester.pump(const Duration(milliseconds: 10));

      verify(() => syncCubit.clearErrorState()).called(1);
      verify(() => syncCubit.retryFailedDrives(['drive-a', 'drive-b']))
          .called(1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failure the user asked for is left to its own modal',
        (tester) async {
      // It has been holding a modal the whole time, and that modal has the
      // same retry in it - see SyncOverlay.
      await tester.pumpWidget(wrap());
      await tester.pump();

      stateController.add(failed(trigger: SyncTrigger.userInitiated));
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Sync Incomplete - Errors Detected'), findsNothing);
      expect(find.text('2 of 5 drives could not be synced'), findsNothing);

      await openMenu(tester);
      expect(find.text('Retry Failed'), findsNothing);

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
      expect(find.text('We could not reach the network to read your drive list.'), findsOneWidget);

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
      // menu the indicator opens.
      await openMenu(tester);

      expect(find.text('Drives Could Not Be Loaded'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);

      entryNamed(tester, 'Try Again').onClick!();
      await tester.pump(const Duration(milliseconds: 10));

      // The request that failed, and not a full sync the user did not ask for.
      verify(() => syncCubit.syncMetadataOnly()).called(1);

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

      // And the retry goes with it - there is nothing left to retry.
      await openMenu(tester);
      expect(find.text('Try Again'), findsNothing);
      expect(find.text('Resync'), findsOneWidget,
          reason: 'precondition: the menu really did open');

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
      expect(find.text('We could not reach the network to read your drive list.'), findsNothing);

      await openMenu(tester);
      expect(find.text('Try Again'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the menu survives what the sync does', () {
    testWidgets('a menu open when a sync starts is still open after it starts',
        (tester) async {
      // Three structurally different subtrees used to occupy this slot, so
      // every transition changed the widget type at that position and took the
      // dropdown's element - and its open flag - with it. A thumb already
      // moving towards Resync landed on the page behind.
      await tester.pumpWidget(wrap());
      await tester.pump();

      await openMenu(tester);
      expect(find.text('Resync'), findsOneWidget,
          reason: 'precondition: the menu is open');

      await startSyncing(tester);

      expect(
        find.text('Resync'),
        findsOneWidget,
        reason: 'a sync starting must not close a menu the user has open',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a menu open when a sync ends is still open after it ends',
        (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      await startSyncing(tester);
      await openMenu(tester);
      expect(find.text('Resync'), findsOneWidget,
          reason: 'precondition: the menu is open during the sync');

      stateController.add(finished(entitiesSynced: 12));
      await tester.pump(const Duration(milliseconds: 10));

      expect(
        find.text('Resync'),
        findsOneWidget,
        reason: 'a sync finishing must not close a menu the user has open',
      );
      // And the result still lands, beside the menu rather than instead of it.
      expect(find.text('12 items changed'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
  testWidgets('a failure that has had its moment is not announced again',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    // SyncCompleteWithErrors stays the cubit's state until the next sync runs.
    // Without a freshness gate the red pill replayed in full on every rebuild
    // of the top bar - i.e. on every drive click, for the rest of the session.
    stateController.add(failed(
      completedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    ));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Sync Incomplete - Errors Detected'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
