import 'dart:async';

import 'package:ardrive/components/app_top_bar.dart';
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
}
