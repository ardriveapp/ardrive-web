import 'dart:async';
import 'dart:io';

import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/app_top_bar.dart';
import 'package:ardrive/models/models.dart';
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

import '../../test_utils/mocks.dart';

/// Every phase the sync layer names for itself, in the words it uses. The
/// repository emits the eight; the cubit emits the ninth on its way in.
const _phases = [
  'Discovering your drives...',
  'Connecting to the network...',
  'Checking for changes...',
  'Downloading drive snapshots...',
  'Reading the drive history...',
  'Creating ghost folders...',
  'Updating transaction statuses...',
  'Completing sync...',
  'Sync complete',
];

/// The two breakpoints the app is laid out for. The header is a tap on both:
/// a phone has no pointer, so a tooltip it cannot reach is not a surface.
const _breakpoints = <String, Size>{
  '320 phone': Size(320, 640),
  '1280 desktop': Size(1280, 800),
};

void main() {
  late MockSyncBloc syncCubit;
  late MockDrivesCubit drivesCubit;
  late StreamController<SyncState> stateController;
  late StreamController<SyncProgress> progressController;

  setUp(() {
    syncCubit = MockSyncBloc();
    drivesCubit = MockDrivesCubit();
    stateController = StreamController<SyncState>.broadcast();
    progressController = StreamController<SyncProgress>.broadcast();

    whenListen(syncCubit, stateController.stream, initialState: SyncIdle());
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
    when(() => syncCubit.syncingDriveId).thenReturn(null);
    when(() => syncCubit.clearCancelledState()).thenReturn(null);
  });

  tearDown(() async {
    await stateController.close();
    await progressController.close();
  });

  Widget host({ArDriveThemeData? theme, double textScale = 1}) {
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<SyncCubit>.value(value: syncCubit),
                BlocProvider<DrivesCubit>.value(value: drivesCubit),
              ],
              // Against the trailing edge, the way both app bars place it.
              child: const Align(
                alignment: Alignment.topRight,
                child: SyncButton(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Puts a running sync on screen, with whatever it is reporting.
  Future<void> startSyncing(
    WidgetTester tester, {
    SyncProgress? reporting,
    String? syncingDriveId,
  }) async {
    if (syncingDriveId != null) {
      when(() => syncCubit.syncingDriveId).thenReturn(syncingDriveId);
    }
    stateController.add(SyncInProgress(trigger: SyncTrigger.background));
    await tester.pump(const Duration(milliseconds: 10));

    if (reporting != null) {
      // Pushed through the stream rather than only stubbed on the cubit. The
      // button's StreamBuilder is mounted in every state, so its `initialData`
      // was read once at the first build and a later stub is never seen -
      // which is exactly the order the app runs in: `SyncInProgress` is
      // emitted first, and the progress arrives behind it.
      when(() => syncCubit.syncProgress).thenReturn(reporting);
      progressController.add(reporting);
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  /// Opens the menu the indicator hangs off, and waits for it to expand.
  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(SyncButton));
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('level 0: a working app says nothing', () {
    testWidgets('a running sync puts no words on screen at all',
        (tester) async {
      // The banner this replaced reported the phase, the elapsed time and a
      // hairline that swept, permanently, above every screen. That is level-2
      // detail forced on somebody who has not asked a question. The ring is
      // the whole of level nought.
      await tester.pumpWidget(host());
      await tester.pump();

      await startSyncing(
        tester,
        reporting: SyncProgress.initial().copyWith(
          statusMessage: 'Reading the drive history...',
          progress: 0.42,
          metadataFetchesCompleted: 340,
          metadataFetchesTotal: 2180,
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'precondition: the ring is turning');

      expect(find.byType(Text), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing,
          reason: 'the hairline is gone, and no other line replaces it');
      expect(find.textContaining('s elapsed'), findsNothing);
      expect(find.textContaining('%'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    test('the shell wraps the page in nothing for the sake of a sync', () {
      // The banner was mounted once, above whatever page the shell was
      // showing. Its absence is a property of this line and of nothing else,
      // so it is read rather than inferred: a wrapper put back here is on
      // every screen again, permanently, for the whole of every sync.
      final shell = File('lib/app_shell.dart').readAsStringSync();

      expect(
        shell.contains('final page = widget.page;'),
        isTrue,
        reason: 'the page reaches both layouts unwrapped, or a sync surface '
            'has been mounted above every screen again',
      );
      final syncSurfaceImports = RegExp(
        r"import 'package:ardrive/sync/presentation/(\w+)\.dart';",
      ).allMatches(shell).map((match) => match.group(1)).toList();

      expect(
        syncSurfaceImports,
        ['sync_overlay'],
        reason: 'the only sync surface the shell may build is the overlay, '
            'which draws nothing at all while a sync is running',
      );
    });
  });

  group('level 1: every phase is one tap away', () {
    for (final phase in _phases) {
      testWidgets('"$phase" is in the header while it is happening',
          (tester) async {
        await tester.pumpWidget(host());
        await tester.pump();

        await startSyncing(
          tester,
          reporting: SyncProgress.initial().copyWith(statusMessage: phase),
        );
        await openMenu(tester);

        expect(
          find.descendant(
            of: find.byKey(syncStatusHeaderKey),
            matching: find.text(phase),
          ),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('a phase that arrives after the menu is open still lands',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();
      await startSyncing(tester);
      await openMenu(tester);

      progressController.add(
        SyncProgress.initial().copyWith(
          statusMessage: 'Creating ghost folders...',
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Creating ghost folders...'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('level 1: the phase that can be counted', () {
    testWidgets('the metadata count beats the phase name it stands in front of',
        (tester) async {
      // Every revision's metadata is its own round trip, a few at a time, and
      // this is the only figure that moves while they are in flight: the
      // percentage is read off block heights the walk has not reached, and the
      // count of what has been found only moves once a whole batch is written.
      await tester.pumpWidget(host());
      await tester.pump();

      await startSyncing(
        tester,
        reporting: SyncProgress.initial().copyWith(
          statusMessage: 'Reading the drive history...',
          metadataFetchesCompleted: 340,
          metadataFetchesTotal: 2180,
        ),
      );
      await openMenu(tester);

      expect(find.text('Reading 340 files...'), findsOneWidget);
      expect(find.text('Reading the drive history...'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('it advances as the fetches come back', (tester) async {
      // Asserting the last figure alone would pass on a header that never
      // moved: the defect this guards is a line that sits still, not a line
      // that ends up wrong.
      await tester.pumpWidget(host());
      await tester.pump();
      await startSyncing(
        tester,
        reporting: SyncProgress.initial().copyWith(
          metadataFetchesCompleted: 0,
          metadataFetchesTotal: 3,
        ),
      );
      await openMenu(tester);

      // Nothing has come back yet, so there is no count worth showing and
      // the phase name stands on its own rather than reading "Reading 0".
      expect(find.text('Reading 0 files...'), findsNothing);

      for (final done in [1, 2, 3]) {
        progressController.add(
          SyncProgress.initial().copyWith(
            metadataFetchesCompleted: done,
            metadataFetchesTotal: 3,
          ),
        );
        await tester.pump(const Duration(milliseconds: 10));

        expect(find.text('Reading $done files...'), findsOneWidget);
      }

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no total, no invented one', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      await startSyncing(
        tester,
        reporting: SyncProgress.initial().copyWith(progress: 0.42),
      );
      await openMenu(tester);

      expect(find.textContaining('Reading'), findsNothing);
      expect(find.text('42% complete'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('level 1: which drive, and for how long', () {
    testWidgets('a single-drive sync names the drive', (tester) async {
      // The banner said "Syncing Drive" and never named it, on either
      // breakpoint. The cubit knows which drive from the first frame; the
      // drives list is the only thing that knows what it is called.
      await tester.pumpWidget(host());
      await tester.pump();

      await startSyncing(
        tester,
        syncingDriveId: 'drive-a',
        reporting: SyncProgress.initial().copyWith(isSingleDriveSync: true),
      );
      await openMenu(tester);

      expect(find.text("Syncing 'Family Photos'..."), findsOneWidget);
      expect(find.text('Syncing Drive'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a drive attached from somebody else is named too',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      await startSyncing(
        tester,
        syncingDriveId: 'drive-b',
        reporting: SyncProgress.initial().copyWith(isSingleDriveSync: true),
      );
      await openMenu(tester);

      expect(find.text("Syncing 'Shared Reports'..."), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a drive the list has not loaded is not given a made-up name',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      await startSyncing(
        tester,
        syncingDriveId: 'drive-nobody-has-heard-of',
        reporting: SyncProgress.initial().copyWith(isSingleDriveSync: true),
      );
      await openMenu(tester);

      expect(find.text('Syncing Drive'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a sync of everything names no drive, because there is none',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      await startSyncing(tester);
      await openMenu(tester);

      expect(find.text('Syncing All Drives'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the elapsed count is in the header, and it keeps counting',
        (tester) async {
      // Counted from the sync's own start - `SyncCubit.syncStartTime` - so the
      // header and the explorer's panel can never disagree about how long this
      // has been going on.
      when(() => syncCubit.syncStartTime)
          .thenReturn(DateTime.now().subtract(const Duration(seconds: 42)));

      await tester.pumpWidget(host());
      await tester.pump();
      await startSyncing(tester);
      await openMenu(tester);

      expect(
        find.descendant(
          of: find.byKey(syncStatusHeaderKey),
          matching: find.text('42s elapsed'),
        ),
        findsOneWidget,
      );

      // And re-read on every tick rather than rendered once. Asserting the
      // first reading alone would pass on a counter that had frozen, which is
      // the defect - a wait that does not count is what a hang looks like.
      // The reading is driven off the wall clock, which a widget test does not
      // advance, so the start time moves instead and the tick has to notice.
      when(() => syncCubit.syncStartTime)
          .thenReturn(DateTime.now().subtract(const Duration(seconds: 97)));
      await tester.pump(const Duration(milliseconds: 1100));

      expect(find.text('42s elapsed'), findsNothing);
      expect(find.text('97s elapsed'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an idle menu counts nothing', (tester) async {
      // `syncStartTime` holds the *last* sync's start, so a header counting
      // from it with nothing running would report minutes of a sync that
      // finished.
      when(() => syncCubit.syncStartTime)
          .thenReturn(DateTime.now().subtract(const Duration(minutes: 9)));

      await tester.pumpWidget(host());
      await tester.pump();
      await openMenu(tester);

      expect(find.byKey(syncStatusHeaderKey), findsNothing);
      expect(find.textContaining('s elapsed'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('level 1: a tap, on both breakpoints', () {
    for (final entry in _breakpoints.entries) {
      testWidgets('${entry.key}: the header opens on a tap', (tester) async {
        // Through the view, not `setSurfaceSize`: that does not reach
        // MediaQuery, and a case that says 320 while running at 800 proves
        // nothing.
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(host());
        await tester.pump();

        await startSyncing(
          tester,
          reporting: SyncProgress.initial().copyWith(
            statusMessage: 'Updating transaction statuses...',
          ),
        );

        expect(find.byKey(syncStatusHeaderKey), findsNothing,
            reason: 'precondition: nothing is said until it is asked for');

        await openMenu(tester);

        expect(find.byKey(syncStatusHeaderKey), findsOneWidget);
        expect(find.text('Updating transaction statuses...'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
      });
    }

    for (final isDark in [false, true]) {
      testWidgets(
          '320 at text scale 2.0 in the ${isDark ? 'dark' : 'light'} theme: '
          'nothing overflows and nothing is clipped', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(host(
          textScale: 2,
          theme: isDark
              ? ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode())
              : lightTheme(),
        ));
        await tester.pump();

        await startSyncing(
          tester,
          syncingDriveId: 'drive-a',
          reporting: SyncProgress.initial().copyWith(
            isSingleDriveSync: true,
            metadataFetchesCompleted: 12345,
            metadataFetchesTotal: 12345,
          ),
        );
        await openMenu(tester);

        // Taken deliberately: an exception left in the drain is an overflow
        // the next test would be blamed for.
        expect(tester.takeException(), isNull);

        final header = find.byKey(syncStatusHeaderKey);
        expect(header, findsOneWidget);

        // On screen, both edges. The menu hangs off the trailing edge and is
        // wider than the room left of the button on a 320px phone; the portal
        // is what pulls it back.
        expect(tester.getTopLeft(header).dx, greaterThanOrEqualTo(0));
        expect(tester.getTopRight(header).dx, lessThanOrEqualTo(320));

        // And the count is scaled down rather than sliced: an unclamped text
        // scale inside a fixed row loses the bottom third of every glyph
        // without a word from the framework - no stripe, no exception.
        final count = tester.renderObject<RenderBox>(
          find.text('Reading 12,345 files...'),
        );
        expect(
          count.size.height,
          count.getMaxIntrinsicHeight(count.size.width),
          reason: 'the count is drawn shorter than it needs to be, so it is '
              'being cut off rather than wrapped',
        );

        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  testWidgets('the menu itself fits a 320px phone at text scale 2.0',
      (tester) async {
    // Not about the header: the rows. Every label in this menu sat in a
    // `MainAxisSize.max` row with no way to give, so at this width and this
    // text scale "Deep Resync" ran 58 pixels past the right edge - in every
    // menu in the app, not only this one. The new row is one more label in
    // the same row.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(textScale: 2));
    await tester.pump();
    await openMenu(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Sync history'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  group('level 1: every state a sync can be in is accounted for', () {
    testWidgets('SyncLoadingDrives says the drive list is being read',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      stateController.add(SyncLoadingDrives());
      await tester.pump(const Duration(milliseconds: 10));
      await openMenu(tester);

      expect(find.text('Loading your drives...'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('SyncInProgress says which sync and what phase',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();
      await startSyncing(
        tester,
        reporting: SyncProgress.initial()
            .copyWith(statusMessage: 'Completing sync...'),
      );
      await openMenu(tester);

      expect(find.text('Syncing All Drives'), findsOneWidget);
      expect(find.text('Completing sync...'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('SyncCompleteWithErrors says how many drives it could not read',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      stateController.add(SyncCompleteWithErrors(
        failedDrives: 2,
        totalDrives: 5,
        failedDriveIds: const ['drive-a'],
        errorMessages: const {'drive-a': 'the gateway said no'},
        completedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ));
      await tester.pump(const Duration(milliseconds: 10));
      await openMenu(tester);

      expect(
        find.descendant(
          of: find.byKey(syncStatusHeaderKey),
          matching: find.text('Sync Incomplete - Errors Detected'),
        ),
        findsOneWidget,
      );
      expect(find.text('2 of 5 drives could not be synced'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('SyncFailure says the drive list itself could not be read',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      stateController.add(SyncFailure(
        error: Exception('the gateway said no'),
        failedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ));
      await tester.pump(const Duration(milliseconds: 10));
      await openMenu(tester);

      expect(
        find.descendant(
          of: find.byKey(syncStatusHeaderKey),
          matching: find.text('Drives Could Not Be Loaded'),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('SyncWalletMismatch says why the user was signed out',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      stateController.add(SyncWalletMismatch());
      await tester.pump(const Duration(milliseconds: 10));
      // Past the few seconds the announcement gets, so this is the header and
      // not the pill.
      await tester.pump(const Duration(seconds: 30));
      await openMenu(tester);

      expect(
        find.descendant(
          of: find.byKey(syncStatusHeaderKey),
          matching: find.text('Wallet Changed'),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('SyncCancelled says what it got through', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      stateController.add(SyncCancelled(
        drivesCompleted: 1,
        totalDrives: 3,
        cancelledAt: DateTime.now(),
      ));
      await tester.pump(const Duration(milliseconds: 10));
      await openMenu(tester);

      expect(
        find.descendant(
          of: find.byKey(syncStatusHeaderKey),
          matching: find.text('Sync Cancelled'),
        ),
        findsOneWidget,
      );
      // Scoped to the header: the announcement pill is saying the same thing
      // beside the indicator for its few seconds, and this test is about the
      // surface that outlives it.
      expect(
        find.descendant(
          of: find.byKey(syncStatusHeaderKey),
          matching: find.text('Completed 1 of 3 drives'),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('SyncComplete is announced, and then it is history',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      stateController.add(SyncComplete(
        entitiesSynced: 12,
        sequence: 1,
        completedAt: DateTime.now(),
        trigger: SyncTrigger.background,
      ));
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('12 items changed'), findsOneWidget);

      // It has nothing to add to the header afterwards - a finished sync is
      // not a running one - so the menu's own door to the record is what
      // carries it from here.
      await tester.pump(const Duration(seconds: 30));
      await openMenu(tester);

      expect(find.byKey(syncStatusHeaderKey), findsNothing);
      expect(find.text('Sync history'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('SyncIdle offers the actions and the record, and says nothing',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();
      await openMenu(tester);

      expect(find.byKey(syncStatusHeaderKey), findsNothing);
      expect(find.text('Resync'), findsOneWidget);
      expect(find.text('Deep Resync'), findsOneWidget);
      expect(find.text('Sync history'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('level 2 is reachable from the indicator', () {
    testWidgets('and its label is readable on the narrowest phone at 2.0x',
        (tester) async {
      // The only door to level 2. A fixed 48px row squeezed the label instead
      // of growing with it, so at 320px and text scale 2.0 the entry read as a
      // cut-off word - the one row a user in trouble is looking for.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(textScale: 2));
      await tester.pump();
      await openMenu(tester);

      final label = tester.renderObject(find.text('Sync history'));
      expect(
        (label as dynamic).didExceedMaxLines,
        isFalse,
        reason: 'the way into the history was truncated',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the menu carries one row, not a list', (tester) async {
      // The dropdown sizes its overlay as `items.length * 48` and closes on
      // any tap inside it, so it is the wrong container for a scrolling
      // record. One row, which opens the modal that holds it.
      await tester.pumpWidget(host());
      await tester.pump();
      await openMenu(tester);

      expect(find.text('Sync history'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('and it is still reachable while a sync is running',
        (tester) async {
      // Resync and Deep Resync are drawn unavailable during a sync; reading
      // what the last few syncs did is not a thing a running sync can refuse,
      // and it is exactly what somebody watching a slow one wants.
      await tester.pumpWidget(host());
      await tester.pump();
      await startSyncing(tester);
      await openMenu(tester);

      final row = tester.widget<ArDriveDropdownItem>(
        find.ancestor(
          of: find.text('Sync history'),
          matching: find.byType(ArDriveDropdownItem),
        ),
      );

      expect(row.onClick, isNotNull);

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
