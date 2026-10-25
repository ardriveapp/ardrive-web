import 'dart:async';

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/search/domain/bloc/search_bloc.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:ardrive/search/domain/search_coverage.dart';
import 'package:ardrive/search/search_box.dart';
import 'package:ardrive/search/search_coverage_notice.dart';
import 'package:ardrive/search/search_modal.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:ardrive/search/search_scope.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../test_utils/mocks.dart';

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockActivityTracker extends Mock implements ActivityTracker {}

class _MockGlobalHideBloc extends MockBloc<GlobalHideEvent, GlobalHideState>
    implements GlobalHideBloc {}

/// The search box acting the way search boxes do: results as you type, keys
/// to move through them, Enter to go, Esc or a click elsewhere to close.
void main() {
  late _MockSearchRepository repository;
  late MockSyncBloc syncCubit;
  late _MockGlobalHideBloc globalHideBloc;
  late MockDrivesCubit drivesCubit;
  late MockDriveDetailCubit driveDetailCubit;
  late _MockActivityTracker activityTracker;
  SearchSession? createdSession;

  // Made inside the test body, on first use, so the search's typing pause
  // runs on the test's clock: a bloc made in setUp schedules it on a real
  // timer, which the test never waits for.
  SearchSession session() => createdSession ??= SearchSession(SearchBloc(
        repository,
        syncCubit: syncCubit,
        globalHideBloc: globalHideBloc,
      ));
  late List<(String, String, String?)> navigations;

  final work = Drive(
    id: 'work',
    rootFolderId: 'work-root',
    ownerAddress: 'me',
    name: 'Work',
    privacy: 'public',
    isHidden: false,
    dateCreated: DateTime(2026),
    lastUpdated: DateTime(2026),
  );

  SearchResult<FileEntry> file(String id, String name, {String? folder}) =>
      SearchResult<FileEntry>(
        result: FileEntry(
          id: id,
          driveId: 'work',
          name: name,
          parentFolderId: folder == null ? 'work-root' : '$folder-id',
          path: '',
          size: 1,
          lastModifiedDate: DateTime(2026),
          dataTxId: 'tx',
          dateCreated: DateTime(2026),
          lastUpdated: DateTime(2026),
          isHidden: false,
        ),
        parentFolder: folder == null
            ? null
            : FolderEntry(
                id: '$folder-id',
                driveId: 'work',
                name: folder,
                path: '',
                dateCreated: DateTime(2026),
                lastUpdated: DateTime(2026),
                isGhost: false,
                isHidden: false,
              ),
        drive: work,
      );

  final report = file('report', 'report.pdf', folder: 'Q3');
  final reports = file('reports', 'reports-2024.zip');

  void searchReturns(String query, List<SearchResult> results) {
    when(() => repository.search(query)).thenAnswer((_) async => results);
  }

  void coverageIs(SearchCoverage coverage) {
    when(() => repository.coverage(
          includeHiddenDrives: any(named: 'includeHiddenDrives'),
        )).thenAnswer((_) async => coverage);
  }

  setUp(() {
    repository = _MockSearchRepository();
    syncCubit = MockSyncBloc();
    globalHideBloc = _MockGlobalHideBloc();
    drivesCubit = MockDrivesCubit();
    driveDetailCubit = MockDriveDetailCubit();
    activityTracker = _MockActivityTracker();
    navigations = [];

    whenListen(syncCubit, const Stream<SyncState>.empty(),
        initialState: SyncIdle());
    when(() => syncCubit.syncingDriveId).thenReturn(null);
    when(() => syncCubit.syncingDriveIds).thenReturn(null);
    whenListen(globalHideBloc, const Stream<GlobalHideState>.empty(),
        initialState: const HiddingItems(userHasHiddenDrive: false));
    when(() => repository.watchDrives())
        .thenAnswer((_) => const Stream.empty());
    when(() => repository.search(any())).thenAnswer((_) async => []);
    coverageIs(const SearchCoverage(totalDrives: 1));
    searchReturns('rep', [report, reports]);
    whenListen(driveDetailCubit, const Stream<DriveDetailState>.empty(),
        initialState: DriveDetailLoadInProgress());
    createdSession = null;
  });

  tearDown(() {
    // Not awaited: the bloc lives on the test's clock, which has stopped, so
    // its close would never finish.
    createdSession?.bloc.close();
  });

  Widget host({Key? boxKey, bool showBox = true}) => ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          // Around the navigator, as in the app: the Portal (main.dart), so
          // the dropdown shares the field's tap region surface, and the
          // session (SearchScope), so the search dialog's route can read it.
          builder: (context, child) => Portal(
            // The search dialog reports itself to it while open.
            child: ChangeNotifierProvider<ActivityTracker>.value(
              value: activityTracker,
              child: RepositoryProvider<SearchSession>.value(
                value: session(),
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider<SearchBloc>.value(value: session().bloc),
                    BlocProvider<DrivesCubit>.value(value: drivesCubit),
                    BlocProvider<DriveDetailCubit>.value(
                      value: driveDetailCubit,
                    ),
                  ],
                  child: child!,
                ),
              ),
            ),
          ),
          home: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showBox)
                  SizedBox(
                    width: 400,
                    child: SearchBox(
                      key: boxKey,
                      onNavigateToFolder: (driveId, folderId, {itemId}) =>
                          navigations.add((driveId, folderId, itemId)),
                    ),
                  ),
                const Expanded(
                  child: SizedBox(
                    key: Key('elsewhere'),
                    width: double.infinity,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> typeQuery(WidgetTester tester, String text) async {
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), text);
    // The pause before searching, then the search.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  /// Enter as the browser delivers it: a key event, and the text field's own
  /// submit. Only one of them may act.
  Future<void> enter(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
  }

  Color? rowColor(WidgetTester tester, String name) {
    final box = tester.widget<ColoredBox>(find
        .ancestor(of: find.text(name), matching: find.byType(ColoredBox))
        .first);
    return box.color;
  }

  bool isHighlighted(WidgetTester tester, String name) =>
      rowColor(tester, name) != Colors.transparent;

  String hint(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).decoration!.hintText!;

  testWidgets('says what it searches, and offers to clear only text',
      (tester) async {
    await tester.pumpWidget(host());

    expect(hint(tester), 'Search files, folders and drives');
    expect(find.byIcon(Icons.close), findsNothing);

    await typeQuery(tester, 'rep');

    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('lists matches under the box as you type, without Enter',
      (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('Work / Q3'), findsOneWidget);
    // At the top of its drive: the drive alone, not the drive twice.
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('See all results'), findsOneWidget);
    expect(find.byType(FileSearchModal), findsNothing);
  });

  testWidgets('Down and Up move through the rows and back to the field',
      (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');

    expect(isHighlighted(tester, 'report.pdf'), isFalse);

    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(isHighlighted(tester, 'report.pdf'), isTrue);

    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(isHighlighted(tester, 'report.pdf'), isFalse);
    expect(isHighlighted(tester, 'reports-2024.zip'), isTrue);

    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(isHighlighted(tester, 'See all results'), isTrue);

    // Past the last row, back to the field with nothing highlighted.
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(isHighlighted(tester, 'See all results'), isFalse);
    expect(isHighlighted(tester, 'report.pdf'), isFalse);

    // Up from the field goes to the last row.
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(isHighlighted(tester, 'See all results'), isTrue);
  });

  testWidgets('Enter goes to the highlighted result, once', (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');
    await key(tester, LogicalKeyboardKey.arrowDown);
    await enter(tester);

    expect(navigations, [('work', 'Q3-id', 'report')]);
    verify(() => drivesCubit.selectDrive('work')).called(1);
    expect(find.byType(FileSearchModal), findsNothing);
    // Closed and emptied, ready for the next search.
    expect(find.text('report.pdf'), findsNothing);
    expect(session().controller.text, isEmpty);
  });

  testWidgets('Enter with nothing highlighted opens every result',
      (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');
    await enter(tester);
    await tester.pumpAndSettle();

    expect(find.byType(FileSearchModal), findsOneWidget);
    expect(navigations, isEmpty);
    // The query carries into the dialog.
    expect(session().controller.text, 'rep');
  });

  // It was drawn in the sign-in card, with its own close button and none of
  // the standard dialog's shadow.
  testWidgets('every result opens in the standard dialog, which closes',
      (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');
    await enter(tester);
    await tester.pumpAndSettle();

    final dialog = find.ancestor(
      of: find.byType(SearchCoverageNotice),
      matching: find.byType(ArDriveStandardModalNew),
    );
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('Search')),
      findsOneWidget,
    );

    await tester.tap(find.descendant(
      of: dialog,
      matching: find.byWidgetPredicate(
        (w) => w is ArDriveIcon && w.icon == ArDriveIconsData.x,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(FileSearchModal), findsNothing);
  });

  testWidgets('the dialog says when nothing matches, and what to try',
      (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'zzz');
    await enter(tester);
    await tester.pumpAndSettle();

    final dialog = find.byType(FileSearchModal);
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('No files, folders or drives match “zzz”.'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('Check the spelling or try another name.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Enter on "See all results" opens every result', (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');
    await key(tester, LogicalKeyboardKey.arrowUp);
    await enter(tester);
    await tester.pumpAndSettle();

    expect(find.byType(FileSearchModal), findsOneWidget);
    expect(navigations, isEmpty);
  });

  testWidgets('a click on a result goes to it', (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');
    await tester.tap(find.text('reports-2024.zip'));
    await tester.pump();

    expect(navigations, [('work', 'work-root', 'reports')]);
  });

  testWidgets('Esc closes the dropdown and keeps the text; Down reopens it',
      (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');
    await key(tester, LogicalKeyboardKey.escape);

    expect(find.text('report.pdf'), findsNothing);
    expect(session().controller.text, 'rep');

    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(find.text('report.pdf'), findsOneWidget);
  });

  testWidgets('a click elsewhere closes it; going back to the box reopens it',
      (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');
    // An empty box, so the tap lands on the page behind it: still outside
    // the field and the dropdown, which is all this needs.
    await tester.tap(find.byKey(const Key('elsewhere')), warnIfMissed: false);
    await tester.pump();

    expect(find.text('report.pdf'), findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.text('report.pdf'), findsOneWidget);
  });

  testWidgets('a mouse resting where the dropdown opens picks nothing',
      (tester) async {
    await tester.pumpWidget(host());

    // The pointer sits still where the first row will appear.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(100, 90));
    addTearDown(gesture.removePointer);

    await typeQuery(tester, 'rep');
    expect(find.text('report.pdf'), findsOneWidget);
    expect(isHighlighted(tester, 'report.pdf'), isFalse);

    await enter(tester);
    await tester.pumpAndSettle();
    expect(navigations, isEmpty);
    expect(find.byType(FileSearchModal), findsOneWidget);
  });

  testWidgets('moving the mouse over a row picks it', (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('reports-2024.zip')));
    await tester.pump();

    expect(isHighlighted(tester, 'reports-2024.zip'), isTrue);
  });

  testWidgets('the highlight stays on its result when the results change',
      (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(isHighlighted(tester, 'reports-2024.zip'), isTrue);

    // Results replaced while the reader is on a row, as after a sync: a new
    // result now sits where the highlighted one was.
    final newer = file('newer', 'rep-new.txt');
    searchReturns('rep', [report, newer, reports]);
    session().bloc.add(const SearchSubmitted('rep'));
    await tester.pump();
    await tester.pump();

    expect(isHighlighted(tester, 'reports-2024.zip'), isTrue);
    expect(isHighlighted(tester, 'rep-new.txt'), isFalse);

    await enter(tester);
    expect(navigations.single.$3, 'reports');
  });

  testWidgets('the last row says how many results there are past the list',
      (tester) async {
    searchReturns('rep', [
      for (var i = 0; i < searchBoxMaxResults + 3; i++)
        file('f$i', 'rep-$i.txt'),
    ]);

    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');

    expect(find.text('See all ${searchBoxMaxResults + 3} results'),
        findsOneWidget);
    expect(find.text('See all results'), findsNothing);
  });

  testWidgets('Esc a second time empties the field', (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');
    await key(tester, LogicalKeyboardKey.escape);
    expect(session().controller.text, 'rep');

    await key(tester, LogicalKeyboardKey.escape);
    expect(session().controller.text, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
  });

  testWidgets('says when nothing matches', (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'zzz');

    expect(
      find.text('No files, folders or drives match “zzz”.'),
      findsOneWidget,
    );
    expect(find.text('See all results'), findsNothing);
  });

  testWidgets('says which drives were not searched, and syncs them',
      (tester) async {
    coverageIs(const SearchCoverage(
      totalDrives: 3,
      unsearchedDriveIds: ['b', 'c'],
    ));
    final syncing = Completer<bool>();
    when(() => syncCubit.syncDrives(any())).thenAnswer((_) => syncing.future);

    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');

    // One line, with the action as a link rather than a boxed button.
    expect(find.textContaining('Searched 1 of 3 drives.'), findsOneWidget);
    expect(find.text('Sync the other 2'), findsOneWidget);
    expect(find.byType(ArDriveButtonNew), findsNothing);

    await tester.tap(find.text('Sync the other 2'));
    await tester.pump();

    verify(() => syncCubit.syncDrives(['b', 'c'])).called(1);
    // Still open: the link is in the dropdown, and took no focus from it.
    expect(find.text('report.pdf'), findsOneWidget);
    expect(
      find.text('Searched 1 of 3 drives. Syncing the other 2 now. Results '
          'update when they finish.'),
      findsOneWidget,
    );
    expect(find.text('Sync the other 2'), findsNothing);

    syncing.complete(true);
  });

  testWidgets('says when no drive was searched', (tester) async {
    coverageIs(SearchCoverage(
      totalDrives: 21,
      unsearchedDriveIds: [for (var i = 0; i < 21; i++) 'd$i'],
    ));

    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');

    expect(
      find.textContaining(
          'None of your 21 drives are synced on this device yet.'),
      findsOneWidget,
    );
    expect(find.text('Sync 21 drives'), findsOneWidget);
  });

  testWidgets('the dialog says it in full, with a button', (tester) async {
    coverageIs(const SearchCoverage(
      totalDrives: 3,
      unsearchedDriveIds: ['b', 'c'],
    ));

    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');
    await enter(tester);
    await tester.pumpAndSettle();

    expect(find.byType(FileSearchModal), findsOneWidget);
    expect(
      find.text('Searched 1 of 3 drives. Sync the other 2 to search them.'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(ArDriveButtonNew, 'Sync 2 drives'),
      findsOneWidget,
    );
  });

  testWidgets('a sync that could not start offers to try again',
      (tester) async {
    coverageIs(const SearchCoverage(
      totalDrives: 3,
      unsearchedDriveIds: ['b', 'c'],
    ));
    when(() => syncCubit.syncDrives(any())).thenAnswer((_) async => false);

    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');
    await tester.tap(find.text('Sync the other 2'));
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining("Searched 1 of 3 drives. Sync couldn't start."),
      findsOneWidget,
    );

    await tester.tap(find.text('Try again'));
    await tester.pump();

    verify(() => syncCubit.syncDrives(['b', 'c'])).called(2);
  });

  testWidgets('says nothing about drives when every one was searched',
      (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');

    expect(find.textContaining('Searched'), findsNothing);
    expect(find.textContaining('Sync'), findsNothing);
  });

  testWidgets('keeps the text when the page rebuilds the box', (tester) async {
    await tester.pumpWidget(host(boxKey: const Key('first')));
    await typeQuery(tester, 'rep');

    // The explorer builds a new top bar for each state of the drive.
    await tester.pumpWidget(host(showBox: false));
    await tester.pumpWidget(host(boxKey: const Key('second')));

    expect(find.text('rep'), findsOneWidget);
  });

  testWidgets('keeps focus and the dropdown when the page rebuilds the box',
      (tester) async {
    await tester.pumpWidget(host(boxKey: const Key('first')));
    await typeQuery(tester, 'rep');
    expect(find.text('report.pdf'), findsOneWidget);

    // A new box in the old one's place, as when a sync brings the drive on
    // screen into view.
    await tester.pumpWidget(host(boxKey: const Key('second')));
    await tester.pump();
    await tester.pump();

    expect(find.text('report.pdf'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
  });

  testWidgets('a box given up on purpose does not take focus back',
      (tester) async {
    await tester.pumpWidget(host(boxKey: const Key('first')));
    await typeQuery(tester, 'rep');
    await key(tester, LogicalKeyboardKey.arrowDown);
    await enter(tester);

    await tester.pumpWidget(host(boxKey: const Key('second')));
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isFalse,
    );
  });

  testWidgets('says how many a sync of only some of them covers',
      (tester) async {
    coverageIs(const SearchCoverage(
      totalDrives: 6,
      unsearchedDriveIds: ['b', 'c', 'd', 'e'],
    ));
    whenListen(syncCubit, const Stream<SyncState>.empty(),
        initialState: SyncInProgress());
    when(() => syncCubit.syncingDriveId).thenReturn('c');

    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');

    expect(
      find.text('Searched 2 of 6 drives. Syncing one of them now. Results '
          'update when it finishes.'),
      findsOneWidget,
    );
  });

  testWidgets('another sync running reads right for one drive', (tester) async {
    coverageIs(const SearchCoverage(
      totalDrives: 1,
      unsearchedDriveIds: ['b'],
    ));
    whenListen(syncCubit, const Stream<SyncState>.empty(),
        initialState: SyncInProgress());
    when(() => syncCubit.syncingDriveId).thenReturn('a');

    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');

    expect(
      find.text("Your drive isn't synced on this device yet. Another sync is "
          'running. You can sync it when that finishes.'),
      findsOneWidget,
    );
    // Nothing to press: only one sync runs at a time.
    expect(find.text('Sync 1 drive'), findsNothing);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a sync that left drives unread says how many, and retries',
      (tester) async {
    coverageIs(const SearchCoverage(
      totalDrives: 3,
      unsearchedDriveIds: ['b', 'c'],
    ));
    when(() => syncCubit.syncDrives(any())).thenAnswer((_) async => true);

    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');
    await tester.tap(find.text('Sync the other 2'));
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining("Searched 1 of 3 drives. 2 drives couldn't be "
          "synced, so their files weren't searched."),
      findsOneWidget,
    );

    await tester.tap(find.text('Try again'));
    await tester.pump();

    verify(() => syncCubit.syncDrives(['b', 'c'])).called(2);
  });

  testWidgets('leaves the arrow keys to an input method while it composes',
      (tester) async {
    await tester.pumpWidget(host());
    await typeQuery(tester, 'rep');

    session().controller.value = const TextEditingValue(
      text: 'rep',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 0, end: 3),
    );
    await tester.pump();
    await key(tester, LogicalKeyboardKey.arrowDown);

    expect(isHighlighted(tester, 'report.pdf'), isFalse);
  });

  testWidgets('a box with nothing typed opens nothing, and Enter does nothing',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await enter(tester);
    await tester.pumpAndSettle();

    expect(find.byType(FileSearchModal), findsNothing);
    expect(find.text('See all results'), findsNothing);
  });
}
