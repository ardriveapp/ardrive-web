import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/drives_list/presentation/drives_list_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
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
  }) =>
      DriveListItem(
        id: id,
        name: id,
        isPrivate: false,
        isSharedWithMe: false,
        isHidden: false,
        dateCreated: DateTime(2024),
        hasBeenWalked: true,
        fileCount: 1,
        totalSize: 1,
        lastSyncedAt: DateTime(2024),
        isSyncing: isSyncing,
        lastSyncFailed: lastSyncFailed,
      );

  var toggled = <String>[];
  var syncedSelected = 0;
  var cleared = 0;
  var retried = 0;

  setUp(() {
    toggled = <String>[];
    syncedSelected = 0;
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
              onSyncAllDrives: () {},
              onToggleSelected: toggled.add,
              onToggleSelectAll: () {},
              onSyncSelected: () => syncedSelected++,
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

    testWidgets('nothing is selected, so no bar is in the way', (tester) async {
      await pump(tester, twoDrives);

      expect(find.text('Sync selected'), findsNothing);
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('a selection says how many and offers one run', (tester) async {
      await pump(
        tester,
        DrivesListLoaded(
          drives: [drive('a'), drive('b')],
          scope: DriveScope.all,
          selected: const {'a', 'b'},
        ),
      );

      expect(find.text('2 drives selected'), findsOneWidget);
      expect(find.text('Sync selected'), findsOneWidget);

      await tester.tap(find.text('Sync selected'));
      await tester.pump();

      expect(syncedSelected, 1);
    });

    testWidgets('and clearing does not select everything instead',
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

      await tester.tap(find.text('Clear'));
      await tester.pump();

      expect(cleared, 1, reason: 'Clear must clear, not toggle-all');
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
}
