import 'dart:async';

import 'package:ardrive/components/app_top_bar.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
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

  Widget host(Widget body) {
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
            body: BlocProvider<SyncCubit>.value(
              value: syncCubit,
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  Widget wrap() => host(const Row(children: [SyncButton()]));

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

  testWidgets('the resync menu survives a running sync', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.byType(ArDriveDropdown), findsOneWidget);

    await startSyncing(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ArDriveDropdown), findsOneWidget);
  });
}
