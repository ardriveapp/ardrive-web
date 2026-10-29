import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/drives_list/presentation/drives_list_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
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
  var chosen = <String>[];
  var opened = <String>[];
  var cleared = 0;
  var retried = 0;

  setUp(() {
    toggled = <String>[];
    chosen = <String>[];
    opened = <String>[];
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
              onOpenDrive: (drive) => opened.add(drive.id),
              onTryAgain: () {},
              onToggleSelected: toggled.add,
              onToggleSelectAll: () {},
              onClearSelection: () => cleared++,
              onRetryFailed: () => retried++,
              onChoose: chosen.add,
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
    // The file-manager pattern (ArDriveMultiSelect), shared with the
    // explorer: a row's box shows while the pointer is on it or it has
    // focus; every box and select-all show while choosing several - once one
    // is ticked, while the multi-select key is held, or after a long press.
    // Ctrl is that key here: the test platform is not macOS or iOS. The
    // column is always reserved, so nothing moves when a box shows.
    List<bool> shown(WidgetTester tester) => tester
        .widgetList<ArDriveMultiSelectBox>(find.byType(ArDriveMultiSelectBox))
        .map((b) => b.visible)
        .toList();

    Future<TestGesture> mouse(WidgetTester tester) async {
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: const Offset(1, 1));
      addTearDown(g.removePointer);
      return g;
    }

    testWidgets('no box shows until a row is pointed at or chosen',
        (tester) async {
      await pump(tester, twoDrives);

      // Select-all, then one per row: all there, none shown.
      expect(shown(tester), [false, false, false]);
      expect(find.text('Name'), findsOneWidget);
    });

    testWidgets("hover shows that row's box only", (tester) async {
      await pump(tester, twoDrives);
      final pointer = await mouse(tester);

      await pointer.moveTo(tester.getCenter(find.text('b')));
      await tester.pumpAndSettle();

      expect(shown(tester), [false, false, true]);
    });

    testWidgets('and a box shown on hover ticks that drive', (tester) async {
      await pump(tester, twoDrives);
      final pointer = await mouse(tester);

      await pointer.moveTo(tester.getCenter(find.text('b')));
      await tester.pumpAndSettle();
      final box = tester.getCenter(find.byKey(const ValueKey('select-b')));
      await pointer.moveTo(box);
      await pointer.down(box);
      await pointer.up();
      await tester.pump();

      expect(toggled, ['b']);
    });

    testWidgets("focus shows that row's box", (tester) async {
      await pump(tester, twoDrives);
      final pointer = await mouse(tester);

      await pointer.down(tester.getCenter(find.text('a')));
      await pointer.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await pointer.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();

      expect(shown(tester), [false, true, false]);
    });

    testWidgets('a tick shows every box and select-all; clearing hides them',
        (tester) async {
      await pump(
        tester,
        DrivesListLoaded(
          drives: [drive('a'), drive('b')],
          scope: DriveScope.all,
          selected: const {'a'},
        ),
      );
      expect(shown(tester), [true, true, true]);
      expect(find.byKey(const ValueKey('select-all')), findsOneWidget);

      await pump(tester, twoDrives);

      expect(shown(tester), [false, false, false]);
    });

    testWidgets('holding the multi-select key shows them all', (tester) async {
      await pump(tester, twoDrives);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(shown(tester), [true, true, true]);

      await tester.tap(find.byKey(const ValueKey('select-b')));
      await tester.pump();
      expect(toggled, ['b']);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(shown(tester), [false, false, false],
          reason: 'released with nothing ticked, they go again');
    });

    testWidgets('a long press shows them on a touch screen', (tester) async {
      await pump(tester, twoDrives);

      await tester.longPress(find.text('a'));
      await tester.pumpAndSettle();

      expect(shown(tester), [true, true, true]);
      expect(toggled, isEmpty, reason: 'a long press ticks nothing itself');

      await tester.longPress(find.text('a'));
      await tester.pumpAndSettle();

      expect(shown(tester), [false, false, false],
          reason: 'a second long press closes them, as in the explorer');
    });

    testWidgets('a click on a row only chooses it, even while choosing several',
        (tester) async {
      await pump(tester, twoDrives);
      final pointer = await mouse(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      // A mouse click: a tap on a touch screen opens the drive instead.
      await pointer.moveTo(tester.getCenter(find.text('b')));
      await pointer.down(tester.getCenter(find.text('b')));
      await pointer.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(chosen.toSet(), {'b'}, reason: 'the click chose the row');
      expect(toggled, isEmpty,
          reason: 'ticking is only the box: it picks what Sync acts on');
    });

    testWidgets('Esc ends a long press with nothing ticked', (tester) async {
      await pump(tester, twoDrives);

      await tester.longPress(find.text('a'));
      await tester.pumpAndSettle();
      expect(shown(tester), [true, true, true]);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(shown(tester), [false, false, false]);
      expect(cleared, 0, reason: 'nothing was ticked to clear');
    });

    testWidgets('a long press on the privacy icon starts selecting too',
        (tester) async {
      // Its tooltip used to take the long press and show its label.
      await pump(tester, twoDrives);

      await tester.longPress(find
          .byWidgetPredicate(
              (w) => w is ArDriveTooltip && w.message == 'Public')
          .first);
      await tester.pumpAndSettle();

      expect(shown(tester), [true, true, true]);
    });

    testWidgets('a hidden box is still a checkbox to a screen reader',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, twoDrives);

      final node = tester.getSemantics(find.byKey(const ValueKey('select-a')));
      expect(
        node,
        matchesSemantics(
          label: 'a',
          hasCheckedState: true,
          isChecked: false,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    /// The list with a selection that really changes, as the page's cubit
    /// changes it.
    Future<void> pumpLive(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var selected = <String>{};

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
              body: StatefulBuilder(
                builder: (context, setState) => DrivesListBody(
                  state: DrivesListLoaded(
                    drives: [drive('a'), drive('b')],
                    scope: DriveScope.all,
                    selected: selected,
                  ),
                  onOpenDrive: (drive) => opened.add(drive.id),
                  onTryAgain: () {},
                  onToggleSelected: (id) => setState(() {
                    toggled.add(id);
                    selected = selected.contains(id)
                        ? ({...selected}..remove(id))
                        : {...selected, id};
                  }),
                  onToggleSelectAll: () {},
                  onClearSelection: () => setState(() => selected = {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
        'the row is the Tab stop: Space ticks its box, again unticks, and '
        'focus stays on the row', (tester) async {
      await pumpLive(tester);

      // Nothing ticked, so select-all is not a stop: the first is row a.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final row = FocusManager.instance.primaryFocus;
      expect(row?.debugLabel, 'ListTableRow');
      expect(shown(tester), [false, true, false],
          reason: 'focus in the row shows its box');

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(toggled, ['a']);
      expect(shown(tester), [true, true, true]);
      expect(FocusManager.instance.primaryFocus, same(row),
          reason: 'a tick keeps focus where it was');

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(toggled, ['a', 'a']);
      expect(FocusManager.instance.primaryFocus, same(row));
      expect(opened, isEmpty, reason: 'Space ticks; it never opens');
    });

    testWidgets('the next Tab is the next row, not its box', (tester) async {
      await pumpLive(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'ListTableRow');
      expect(shown(tester), [false, false, true]);
    });

    testWidgets('a tap where a hidden box sits is a tap on the row',
        (tester) async {
      await pump(tester, twoDrives);

      // Touch opens, per the row model; the box's spot is not dead.
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('select-a'))),
        kind: PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();

      expect(opened, ['a']);
      expect(toggled, isEmpty);
    });

    testWidgets('names and headings do not move when the boxes show',
        (tester) async {
      await pump(tester, twoDrives);
      final before = [
        tester.getTopLeft(find.text('a')),
        tester.getTopLeft(find.text('Name')),
      ];

      await pump(
        tester,
        DrivesListLoaded(
          drives: [drive('a'), drive('b')],
          scope: DriveScope.all,
          selected: const {'a'},
        ),
      );

      expect(tester.getTopLeft(find.text('a')), before[0]);
      expect(tester.getTopLeft(find.text('Name')), before[1]);
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
