import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/sync/domain/sync_run.dart';
import 'package:ardrive/sync/domain/sync_trigger.dart';
import 'package:ardrive/sync/presentation/sync_history_panel.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

/// Real rather than mocked: it is a [ChangeNotifier], which is what the modal
/// is provided with in the app, and the only thing this test asks of it is
/// that it exists.
class _StubActivityTracker extends ActivityTracker {}

/// The instant every relative time in this file is counted back from, so
/// "12 minutes ago" means twelve minutes and not "whenever the test ran".
final _now = DateTime(2026, 8, 31, 12);

void main() {
  late _MockUserPreferencesRepository preferences;
  late _StubActivityTracker activityTracker;

  setUp(() {
    preferences = _MockUserPreferencesRepository();
    activityTracker = _StubActivityTracker();
    when(() => preferences.loadSyncHistory()).thenAnswer((_) async => const []);
  });

  SyncRun run({
    Duration ago = const Duration(minutes: 12),
    Duration took = const Duration(seconds: 8),
    SyncTrigger trigger = SyncTrigger.background,
    SyncRunOutcome outcome = SyncRunOutcome.completed,
    String? driveName,
    int itemsFound = 0,
    int skippedEntityCount = 0,
    int failedDrives = 0,
    int totalDrives = 0,
    Map<String, String> errorMessages = const {},
  }) =>
      SyncRun(
        startedAt: _now.subtract(ago),
        took: took,
        trigger: trigger,
        outcome: outcome,
        driveName: driveName,
        itemsFound: itemsFound,
        skippedEntityCount: skippedEntityCount,
        failedDrives: failedDrives,
        totalDrives: totalDrives,
        errorMessages: errorMessages,
      );

  void historyIs(List<SyncRun> runs) {
    when(() => preferences.loadSyncHistory()).thenAnswer((_) async => runs);
  }

  Widget host(Widget body, {ArDriveThemeData? theme, double textScale = 1}) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<UserPreferencesRepository>.value(value: preferences),
        ChangeNotifierProvider<ActivityTracker>.value(value: activityTracker),
      ],
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
          home: Scaffold(body: body),
        ),
      ),
    );
  }

  /// The panel on its own, with the clock pinned.
  Future<void> pumpPanel(
    WidgetTester tester, {
    ArDriveThemeData? theme,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      host(
        SingleChildScrollView(child: SyncHistoryPanel(now: _now)),
        theme: theme,
        textScale: textScale,
      ),
    );
    // One frame for the local read to come back.
    await tester.pump();
  }

  group('a wallet that has never synced', () {
    testWidgets('reads as nothing yet, not as an error and not as a blank',
        (tester) async {
      historyIs(const []);

      await pumpPanel(tester);

      expect(
        find.text('Nothing has synced on this device yet.'),
        findsOneWidget,
      );
      expect(
          find.text('Syncs are listed here as they finish.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('a run that finished', () {
    testWidgets('says what it was, when, who asked, how long and what it found',
        (tester) async {
      historyIs([run(itemsFound: 12)]);

      await pumpPanel(tester);

      expect(find.text('All drives'), findsOneWidget);
      expect(
        find.text('12 minutes ago · automatic · took 8s'),
        findsOneWidget,
      );
      expect(find.text('12 new items'), findsOneWidget);
    });

    testWidgets('a sync that changed nothing still says so', (tester) async {
      // The case the record exists for: told nothing changed, the user can
      // stop wondering whether the sync ran at all.
      historyIs([run(itemsFound: 0)]);

      await pumpPanel(tester);

      expect(find.text('Nothing new'), findsOneWidget);
    });

    testWidgets('a sync of one drive is titled with the drive', (tester) async {
      historyIs([run(driveName: 'Family Photos', itemsFound: 4)]);

      await pumpPanel(tester);

      expect(find.text('Family Photos'), findsOneWidget);
      expect(find.text('All drives'), findsNothing);
    });

    testWidgets('a sync the user asked for says so', (tester) async {
      historyIs([run(trigger: SyncTrigger.userInitiated)]);

      await pumpPanel(tester);

      expect(
        find.text('12 minutes ago · started by you · took 8s'),
        findsOneWidget,
      );
    });

    testWidgets('a long sync is minutes and seconds, not a count of seconds',
        (tester) async {
      // Eleven minutes is the whole reason for writing this down, and "660s"
      // is not a number anybody reads.
      historyIs([run(took: const Duration(minutes: 2, seconds: 14))]);

      await pumpPanel(tester);

      expect(find.textContaining('took 2m 14s'), findsOneWidget);
    });

    testWidgets('items it could not read are reported on a clean run too',
        (tester) async {
      // A sync can finish with every drive read and still have dropped files
      // whose metadata would not load. A user who is not told is looking at a
      // drive with holes in it beside a panel saying it went well.
      historyIs([run(itemsFound: 12, skippedEntityCount: 3)]);

      await pumpPanel(tester);

      expect(find.text('12 new items'), findsOneWidget);
      expect(find.text('3 items could not be read'), findsOneWidget);
    });
  });

  group('when it happened', () {
    testWidgets('less than a minute ago', (tester) async {
      historyIs([run(ago: const Duration(seconds: 30))]);
      await pumpPanel(tester);
      expect(find.textContaining('Just now · '), findsOneWidget);
    });

    testWidgets('within the hour', (tester) async {
      historyIs([run(ago: const Duration(minutes: 1))]);
      await pumpPanel(tester);
      expect(find.textContaining('1 minute ago · '), findsOneWidget);
    });

    testWidgets('within the day', (tester) async {
      historyIs([run(ago: const Duration(hours: 3))]);
      await pumpPanel(tester);
      expect(find.textContaining('3 hours ago · '), findsOneWidget);
    });

    testWidgets('and a date once a count of hours stops meaning anything',
        (tester) async {
      historyIs([run(ago: const Duration(days: 2))]);
      await pumpPanel(tester);
      // The time of day as well as the date: "which sync was that" is usually
      // a question about a particular morning.
      expect(find.textContaining('Aug 29, 2026 12:00 PM · '), findsOneWidget);
    });
  });

  group('a run that went wrong', () {
    testWidgets('drives that could not be read are counted and quoted',
        (tester) async {
      historyIs([
        run(
          outcome: SyncRunOutcome.completedWithErrors,
          itemsFound: 5,
          failedDrives: 2,
          totalDrives: 5,
          errorMessages: const {'drive-a': 'the gateway said no'},
        )
      ]);

      await pumpPanel(tester);

      expect(find.text('5 new items'), findsOneWidget);
      expect(find.text('2 of 5 drives could not be synced'), findsOneWidget);
      // Verbatim. A user reading this is a button away from sending the logs
      // beside it to support, and a paraphrase is not something support can
      // search for.
      expect(find.text('the gateway said no'), findsOneWidget);
    });

    testWidgets('a sync that could not be done at all says so', (tester) async {
      historyIs([run(outcome: SyncRunOutcome.failed)]);

      await pumpPanel(tester);

      expect(
        find.text('This sync could not be done, so nothing was read.'),
        findsOneWidget,
      );
    });

    testWidgets('a sync that was stopped part way says so', (tester) async {
      historyIs([run(outcome: SyncRunOutcome.cancelled)]);

      await pumpPanel(tester);

      expect(
        find.text('This sync was stopped before it finished.'),
        findsOneWidget,
      );
    });

    testWidgets('and it is drawn as a problem, not as a result',
        (tester) async {
      historyIs([run(outcome: SyncRunOutcome.failed)]);

      await pumpPanel(tester);

      final colorTokens = lightTheme().colorTokens;
      final line = tester.widget<Text>(
        find.text('This sync could not be done, so nothing was read.'),
      );

      expect(line.style?.color, colorTokens.textRed);
      expect(line.style?.color, isNot(colorTokens.textMid));
    });
  });

  testWidgets('every recent run is listed, newest first', (tester) async {
    historyIs([
      run(ago: const Duration(minutes: 1), driveName: 'Newest'),
      run(ago: const Duration(minutes: 30), driveName: 'Middle'),
      run(ago: const Duration(hours: 5), driveName: 'Oldest'),
    ]);

    await pumpPanel(tester);

    expect(find.byType(SyncRunTile), findsNWidgets(3));
    expect(
      tester.getTopLeft(find.text('Newest')).dy,
      lessThan(tester.getTopLeft(find.text('Middle')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Middle')).dy,
      lessThan(tester.getTopLeft(find.text('Oldest')).dy),
    );
  });

  group('it holds the narrowest phone at the largest text', () {
    for (final isDark in [false, true]) {
      testWidgets('320 at text scale 2.0, ${isDark ? 'dark' : 'light'}',
          (tester) async {
        // Through the view, not `setSurfaceSize`: that does not reach
        // MediaQuery, and a case that says 320 while running at 800 proves
        // nothing.
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        historyIs([
          run(
            driveName: 'Family Photos And Videos Nineteen Ninety Nine To Today',
            outcome: SyncRunOutcome.completedWithErrors,
            itemsFound: 12345,
            skippedEntityCount: 3,
            failedDrives: 2,
            totalDrives: 5,
            errorMessages: const {
              'drive-a':
                  'the gateway returned 502 while reading the drive history',
            },
            took: const Duration(minutes: 11, seconds: 3),
          ),
        ]);

        await pumpPanel(
          tester,
          textScale: 2,
          theme: isDark
              ? ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode())
              : lightTheme(),
        );

        // Taken deliberately: an exception left in the drain is an overflow
        // the next test gets blamed for.
        expect(tester.takeException(), isNull);
        expect(find.byType(SyncRunTile), findsOneWidget);
        expect(tester.getTopLeft(find.byType(SyncRunTile)).dx,
            greaterThanOrEqualTo(0));
        expect(
          tester.getSize(find.byType(SyncRunTile)).width,
          lessThanOrEqualTo(320),
        );
      });
    }
  });

  group('it has a modal of its own', () {
    /// Opens the record the way the sync menu's "Sync history" row opens it.
    Future<void> openHistoryModal(WidgetTester tester,
        {double textScale = 1}) async {
      await tester.pumpWidget(host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showSyncHistoryModal(context),
            child: const Text('open'),
          ),
        ),
        textScale: textScale,
      ));
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('titled as the thing it is, with the record inside',
        (tester) async {
      historyIs([run(itemsFound: 12)]);

      await openHistoryModal(tester);

      expect(find.byType(SyncHistoryPanel), findsOneWidget);
      expect(find.text('All drives'), findsOneWidget);
      expect(find.text('12 new items'), findsOneWidget);
      // The record is the whole modal. Nothing from Help came with it - it is
      // no longer the sixth section of a page about support links.
      expect(find.text('Troubleshooting'), findsNothing);
      expect(find.text('Download'), findsNothing);
    });

    testWidgets('and it says what the record covers', (tester) async {
      historyIs([run()]);

      await openHistoryModal(tester);

      expect(
        find.text(
          'What the most recent syncs did on this device. '
          'The last $syncHistoryLimit are kept, and they go when you log out.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a full record scrolls rather than clipping', (tester) async {
      // Twenty runs at 320 and text scale 2.0 is far taller than the screen.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      historyIs(
          [for (var i = 0; i < syncHistoryLimit; i++) run(itemsFound: i)]);

      await openHistoryModal(tester, textScale: 2);

      expect(tester.takeException(), isNull);
      expect(find.byType(SyncHistoryPanel), findsOneWidget);
    });
  });

  group('and Help points at it rather than carrying it', () {
    testWidgets('the Troubleshooting section offers it as a link',
        (tester) async {
      historyIs([run(itemsFound: 12)]);

      await tester.pumpWidget(host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showSupportModal(context: context),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The link, not the record: Help stays a page about getting help.
      expect(find.text('Troubleshooting'), findsOneWidget);
      expect(find.text('Sync history'), findsOneWidget);
      expect(find.byType(SyncHistoryPanel), findsNothing);
      expect(find.text('12 new items'), findsNothing);
      // The log export is still the modal's own action.
      expect(find.text('Download'), findsOneWidget);

      // The modal scrolls, and the link sits below the fold on a default
      // test viewport - tapping it where it is not would hit the page behind.
      await tester.ensureVisible(find.text('Sync history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync history'));
      await tester.pumpAndSettle();

      // And following it lands on the record, drawn over Help.
      expect(find.byType(SyncHistoryPanel), findsOneWidget);
      expect(find.text('12 new items'), findsOneWidget);
    });
  });
}
