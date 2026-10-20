import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/drives_list/presentation/drives_list_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Choosing a few drives to sync, and being told when some could not be read.
///
/// The engine could always walk an arbitrary subset concurrently - the retry
/// path has used it for as long as it has existed. What was missing was any
/// way to say which, and any summary of what a partial failure actually cost.
void main() {
  DriveListItem drive(
    String id, {
    bool lastSyncFailed = false,
    bool isSyncing = false,
    bool hasBeenWalked = true,
  }) =>
      DriveListItem(
        id: id,
        name: id,
        isPrivate: false,
        isSharedWithMe: false,
        isHidden: false,
        dateCreated: DateTime(2024),
        hasBeenWalked: hasBeenWalked,
        fileCount: hasBeenWalked ? 1 : null,
        totalSize: hasBeenWalked ? 1 : null,
        lastSyncedAt: hasBeenWalked ? DateTime(2024) : null,
        isSyncing: isSyncing,
        lastSyncFailed: lastSyncFailed,
      );

  var toggled = <String>[];
  var cleared = 0;
  var retried = 0;

  setUp(() {
    toggled = <String>[];
    cleared = 0;
    retried = 0;
  });

  Future<void> pump(
    WidgetTester tester,
    DrivesListLoaded state, {
    double width = 1200,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ArDriveTheme(
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
            body: DrivesListBody(
              state: state,
              onOpenDrive: (_) {},
              onTryAgain: () {},
              onToggleSelected: toggled.add,
              onToggleSelectAll: () {},
              onClearSelection: () => cleared++,
              onRetryFailed: () => retried++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final twoDrives = DrivesListLoaded(
    drives: [drive('a'), drive('b')],
    scope: DriveScope.all,
  );

  group('choosing drives', () {
    testWidgets('every row offers a tick', (tester) async {
      await pump(tester, twoDrives);

      expect(find.byType(ArDriveCheckBox), findsNWidgets(3),
          reason: 'one per row, plus the header select-all');
    });

    testWidgets('nothing is selected, so the heading is the page\'s title',
        (tester) async {
      await pump(tester, twoDrives);

      expect(find.text('Your drives'), findsOneWidget);
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('a selection becomes the heading, saying how many',
        (tester) async {
      await pump(
        tester,
        DrivesListLoaded(
          drives: [drive('a'), drive('b')],
          scope: DriveScope.all,
          selected: const {'a', 'b'},
        ),
      );

      expect(find.text('2 drives selected'), findsOneWidget);
      expect(find.text('Your drives'), findsNothing);
      // What to do with them is the page's one sync button, not a second
      // button beside the count.
      expect(find.text('Sync selected'), findsNothing);
    });

    testWidgets('the x clears it, and does not select everything instead',
        (tester) async {
      await pump(
        tester,
        DrivesListLoaded(
          drives: [drive('a'), drive('b')],
          scope: DriveScope.all,
          selected: const {'a'},
        ),
      );

      expect(find.text('1 drive selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear selection'));
      await tester.pump();

      expect(cleared, 1, reason: 'the x must clear, not toggle-all');
    });

    testWidgets('and so does Esc', (tester) async {
      await pump(
        tester,
        DrivesListLoaded(
          drives: [drive('a'), drive('b')],
          scope: DriveScope.all,
          selected: const {'a'},
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(cleared, 1);
    });

    testWidgets('but Esc is left alone when nothing is ticked', (tester) async {
      await pump(tester, twoDrives);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(cleared, 0,
          reason: 'with nothing to clear, Esc belongs to whatever is around '
              'the list - the drive details panel closes on it');
    });
  });

  group('a sync that read some drives and not others', () {
    final partlyFailed = DrivesListLoaded(
      drives: [drive('a'), drive('b', lastSyncFailed: true)],
      scope: DriveScope.all,
    );

    testWidgets('adds up what failed and offers exactly that retry',
        (tester) async {
      await pump(tester, partlyFailed);

      expect(find.text('1 of 2 drives could not be read'), findsOneWidget);

      await tester.tap(find.text('Sync that drive'));
      await tester.pump();

      expect(retried, 1);
    });

    testWidgets('says nothing was lost, because nothing was', (tester) async {
      await pump(tester, partlyFailed);

      expect(
        find.textContaining('keeps whatever was read last time'),
        findsOneWidget,
        reason: 'a reader looking at red needs telling what is still true',
      );
    });

    testWidgets('and holds its tongue while a sync is running', (tester) async {
      await pump(
        tester,
        DrivesListLoaded(
          drives: [
            drive('a', isSyncing: true),
            drive('b', lastSyncFailed: true, isSyncing: true),
          ],
          scope: DriveScope.all,
        ),
      );

      expect(
        find.textContaining('could not be read'),
        findsNothing,
        reason: 'the run under way may well fix it; reporting the last one as '
            'though it were the current answer is the error this whole series '
            'exists to remove',
      );
    });

    testWidgets('nothing is said when every drive was read', (tester) async {
      await pump(tester, twoDrives);

      expect(find.textContaining('could not be read'), findsNothing);
    });
  });

  /// The two things the first version of this got wrong, both visible in a
  /// screenshot: the column headings vanished, and two red buttons offering
  /// different scopes sat a hundred pixels apart. And the one the strip that
  /// fixed them got wrong: appearing above the table, it moved every row down
  /// on the first tick.
  group('a selection does not cost the table its headings', () {
    final oneTicked = DrivesListLoaded(
      drives: [drive('a'), drive('b')],
      scope: DriveScope.all,
      selected: const {'a'},
    );

    testWidgets('the columns are still labelled while selecting',
        (tester) async {
      await pump(tester, oneTicked);

      for (final heading in ['Name', 'Last synced', 'Files', 'Size']) {
        expect(
          find.text(heading),
          findsOneWidget,
          reason: '"$heading" is what makes a column of dashes readable',
        );
      }
    });

    testWidgets('and ticking a drive moves nothing below the heading',
        (tester) async {
      await pump(tester, twoDrives);
      final before = tester.getTopLeft(find.text('Name'));

      await pump(tester, oneTicked);
      final after = tester.getTopLeft(find.text('Name'));

      expect(after, before,
          reason: 'the heading becomes the selection in place; a row of its '
              'own pushed the list down under the pointer');
    });

    testWidgets('nor does it while nothing has synced yet', (tester) async {
      DrivesListLoaded neverSynced({Set<String> selected = const {}}) =>
          DrivesListLoaded(
            drives: [
              drive('a', hasBeenWalked: false),
              drive('b', hasBeenWalked: false),
            ],
            scope: DriveScope.all,
            selected: selected,
          );

      await pump(tester, neverSynced());
      final before = tester.getTopLeft(find.text('Name'));
      expect(find.text('Nothing has been synced yet'), findsOneWidget);

      await pump(tester, neverSynced(selected: const {'a'}));

      // The card stays: it is words now, and withdrawing it on the first
      // tick was the same jump.
      expect(find.text('Nothing has been synced yet'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Name')), before);
    });

    testWidgets('and the title comes back when nothing is ticked',
        (tester) async {
      await pump(tester, oneTicked);
      expect(find.text('Your drives'), findsNothing);

      await pump(tester, twoDrives);

      expect(find.text('Your drives'), findsOneWidget);
      expect(find.textContaining('selected'), findsNothing);
    });
  });
}
