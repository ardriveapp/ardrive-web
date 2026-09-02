import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/presentation/drive_list_row.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/drives_list/presentation/drives_list_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The four answers the page is allowed to give, rendered.
///
/// The rule they exist to enforce: only one of them may say the user has no
/// drives, and it is the only one that may offer to create one. The other
/// three have each been drawn as that one at some point in this app's history,
/// which is what stranded people on login.
void main() {
  DriveListItem drive({
    required String id,
    required String name,
    bool hasBeenWalked = true,
    bool isSharedWithMe = false,
  }) =>
      DriveListItem(
        id: id,
        name: name,
        isPrivate: false,
        isSharedWithMe: isSharedWithMe,
        isHidden: false,
        dateCreated: DateTime(2024, 3, 4),
        hasBeenWalked: hasBeenWalked,
        fileCount: hasBeenWalked ? 2 : null,
        totalSize: hasBeenWalked ? 100 : null,
        lastSyncedAt: hasBeenWalked ? DateTime.now() : null,
        isSyncing: false,
        lastSyncFailed: false,
      );

  var opened = <String>[];
  var triedAgain = 0;
  var syncedAll = 0;

  setUp(() {
    opened = <String>[];
    triedAgain = 0;
    syncedAll = 0;
  });

  Future<void> pumpBody(
    WidgetTester tester,
    DrivesListState state, {
    double width = 1200,
    double height = 900,
    bool dark = false,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ArDriveTheme(
        // Passing no theme data is how ArDriveTheme yields the dark theme.
        themeData: dark ? null : lightTheme(),
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
              onTryAgain: () => triedAgain++,
              onSyncAllDrives: () => syncedAll++,
            ),
          ),
        ),
      ),
    );
  }

  /// The chrome that makes this list read as the same component as every
  /// other table in the app, rather than as a spreadsheet parked on the page.
  ///
  /// `ArDriveDataTable` - the explorer, the move and hide dialogs, the licence
  /// form, the shared-file view - puts its header and rows in an `ArDriveCard`
  /// on `tableTheme.backgroundColor` and draws no line between rows. This list
  /// did neither, which is what made it look like a different product.
  group('the table chrome matches the rest of the app', () {
    final twoDrives = DrivesListLoaded(
      drives: [
        drive(id: 'a', name: 'Photos'),
        drive(id: 'b', name: 'Work'),
      ],
    );

    Finder panelWithTableGround(WidgetTester tester) {
      final ground = lightTheme().tableTheme.backgroundColor;

      return find.byWidgetPredicate((widget) {
        if (widget is! DecoratedSliver) return false;
        final decoration = widget.decoration;
        return decoration is BoxDecoration && decoration.color == ground;
      });
    }

    testWidgets('the columns layout sits on the shared table ground',
        (tester) async {
      await pumpBody(tester, twoDrives);

      expect(
        panelWithTableGround(tester),
        findsOneWidget,
        reason: 'the header and rows belong in the same panel every other '
            'table uses, not straight on the page ground',
      );
    });

    testWidgets('rows inside the panel draw no rule between them',
        (tester) async {
      await pumpBody(tester, twoDrives);

      final rows = tester.widgetList<DriveListRow>(find.byType(DriveListRow));
      expect(rows, hasLength(2), reason: 'precondition: both drives drawn');

      for (final row in rows) {
        expect(row.showsColumns, isTrue,
            reason: 'precondition: this is the columns layout');
      }

      // The explorer separates rows with the panel ground and hover alone.
      final borders = tester
          .widgetList<Container>(
        find.descendant(
          of: find.byType(DriveListRow),
          matching: find.byType(Container),
        ),
      )
          .where((c) {
        final decoration = c.decoration;
        return decoration is BoxDecoration && decoration.border != null;
      });

      expect(borders, isEmpty,
          reason: 'a hairline under every row is what made this read as a '
              'spreadsheet rather than a panel');
    });

    testWidgets('a phone gets no panel, and keeps its rules', (tester) async {
      await pumpBody(tester, twoDrives, width: 320, height: 640);

      final rows = tester.widgetList<DriveListRow>(find.byType(DriveListRow));
      expect(rows.every((row) => !row.showsColumns), isTrue,
          reason: 'precondition: this is the stacked layout');

      expect(
        panelWithTableGround(tester),
        findsNothing,
        reason: 'the stacked row is its own block and the explorer draws no '
            'panel behind its phone tiles either',
      );
    });
  });

  group('loading', () {
    testWidgets('says it is still looking, and never that there are none',
        (tester) async {
      await pumpBody(tester, const DrivesListLoading());

      expect(find.text('Loading your drives...'), findsOneWidget);
      expect(find.text('Getting Started'), findsNothing);
      expect(find.text('Create new public drive'), findsNothing);
    });
  });

  group('empty', () {
    testWidgets('is the one state that offers to create a drive',
        (tester) async {
      await pumpBody(tester, DrivesListEmpty());

      expect(find.text('Getting Started'), findsOneWidget);
      expect(find.text('Create new public drive'), findsOneWidget);
      expect(find.text('Create new private drive'), findsOneWidget);
    });
  });

  group('could not be loaded', () {
    testWidgets('says what happened and offers to try again', (tester) async {
      await pumpBody(tester, DrivesListUnavailable());

      expect(find.text('Your Drives Could Not Be Loaded'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('never offers to create a drive instead', (tester) async {
      await pumpBody(tester, DrivesListUnavailable());

      expect(find.text('Getting Started'), findsNothing);
      expect(find.text('Create new public drive'), findsNothing);
      expect(find.text('Create new private drive'), findsNothing);
    });

    testWidgets('trying again is what the button does', (tester) async {
      await pumpBody(tester, DrivesListUnavailable());
      await tester.tap(find.text('Try Again'));

      expect(triedAgain, 1);
    });
  });

  group('the list', () {
    final twoDrives = DrivesListLoaded(
      drives: [
        drive(id: 'a', name: 'Photos'),
        drive(id: 'b', name: 'Work', isSharedWithMe: true),
      ],
    );

    testWidgets('draws every drive, owned and attached, as one list',
        (tester) async {
      await pumpBody(tester, twoDrives);

      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Shared with me'), findsOneWidget);
      expect(find.byType(DriveListRow), findsNWidgets(2));
    });

    testWidgets('opening one hands it back', (tester) async {
      await pumpBody(tester, twoDrives);
      await tester.tap(find.text('Work'));

      expect(opened, ['b']);
    });

    testWidgets('a wide screen gets column headings', (tester) async {
      await pumpBody(tester, twoDrives);

      expect(find.byType(DriveListHeader), findsOneWidget);
      expect(find.text('Last synced'), findsOneWidget);
    });

    testWidgets('a phone does not, because it has no columns', (tester) async {
      await pumpBody(tester, twoDrives, width: 320);

      expect(find.byType(DriveListHeader), findsNothing);
      // Still the whole list, and still no overflow.
      expect(find.byType(DriveListRow), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders at 390 and in the dark without overflowing',
        (tester) async {
      await pumpBody(tester, twoDrives, width: 390, dark: true);

      expect(find.byType(DriveListRow), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('offers one sync when nothing has ever been synced',
        (tester) async {
      await pumpBody(
        tester,
        DrivesListLoaded(
          drives: [
            drive(id: 'a', name: 'Photos', hasBeenWalked: false),
            drive(id: 'b', name: 'Work', hasBeenWalked: false),
          ],
        ),
      );

      expect(find.text('Nothing has been synced yet'), findsOneWidget);

      await tester.tap(find.text('Sync All Drives'));
      expect(syncedAll, 1);
    });

    testWidgets('and stops offering it once one drive has been synced',
        (tester) async {
      await pumpBody(
        tester,
        DrivesListLoaded(
          drives: [
            drive(id: 'a', name: 'Photos', hasBeenWalked: true),
            drive(id: 'b', name: 'Work', hasBeenWalked: false),
          ],
        ),
      );

      // The per-drive answer is on the row by then; a banner over the top of
      // it would be a nag, not information.
      expect(find.text('Nothing has been synced yet'), findsNothing);
      expect(find.text('Sync All Drives'), findsNothing);
    });

    testWidgets('the sync-everything offer fits a 320px screen',
        (tester) async {
      await pumpBody(
        tester,
        DrivesListLoaded(
          drives: [drive(id: 'a', name: 'Photos', hasBeenWalked: false)],
        ),
        width: 320,
      );

      expect(find.text('Sync All Drives'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the header and the rows agree', () {
    // One drive, so the geometry below has one of each text to measure.
    final oneDrive = DrivesListLoaded(drives: [drive(id: 'a', name: 'Photos')]);

    /// Which layout the rows are actually in, read off the geometry.
    bool rowsAreStacked(WidgetTester tester) {
      final nameX = tester.getTopLeft(find.text('Photos')).dx;
      final itemsX = tester.getTopLeft(find.text('2 files')).dx;

      return itemsX < nameX;
    }

    /// The whole band the two used to disagree across, not the two widths
    /// where they happened to agree.
    ///
    /// The header was decided on the body's width and each row decided again
    /// on its own - inside 16px of padding either side - so between them a
    /// table header sat over a column of cards. That band was reachable at an
    /// ordinary desktop window size.
    for (var width = 640.0; width <= 1000.0; width += 20) {
      testWidgets('at ${width.toInt()}px they are the same layout',
          (tester) async {
        await pumpBody(tester, oneDrive, width: width);

        // A "width" that the surface silently clamped is not a width. This is
        // the trap that made a previous pass of this test render the same
        // branch twice under two names.
        expect(tester.getSize(find.byType(DrivesListBody)).width, width);

        final hasHeader = find.byType(DriveListHeader).evaluate().isNotEmpty;

        expect(
          hasHeader,
          !rowsAreStacked(tester),
          reason: hasHeader
              ? 'a table header over stacked cards at ${width.toInt()}px'
              : 'columns with no heading over them at ${width.toInt()}px',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the shape of the page', () {
    final neverSynced = DrivesListLoaded(
      drives: [
        drive(id: 'a', name: 'Photos', hasBeenWalked: false),
        drive(id: 'b', name: 'Work', hasBeenWalked: false),
      ],
    );

    testWidgets('the sync-everything button is a button, not a slab',
        (tester) async {
      await pumpBody(tester, neverSynced, width: 1280);

      final button = tester.getSize(
        find.widgetWithText(ArDriveButtonNew, 'Sync All Drives'),
      );

      // With no width of its own the button expands to the content column:
      // about 1200px of primary colour, on the one screen whose message is
      // that nothing is wrong yet.
      expect(button.width, lessThan(320));

      await tester.tap(find.text('Sync All Drives'));
      expect(syncedAll, 1);
    });

    testWidgets('a phone in landscape can still reach its drives',
        (tester) async {
      // 568x264 - a small phone on its side, and also a portrait phone at a
      // large text scale. The sync-everything card alone is taller than this.
      await pumpBody(tester, neverSynced, width: 568, height: 264);

      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(DrivesListBody), const Offset(0, -400));
      await tester.pumpAndSettle();

      // Nothing scrolled at all when the list was the only scrolling part of
      // a fixed column: it was given no height to scroll in.
      expect(find.text('Photos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the list does not stretch across a 1920 monitor',
        (tester) async {
      await pumpBody(
        tester,
        DrivesListLoaded(drives: [drive(id: 'a', name: 'Photos')]),
        width: 1920,
      );

      expect(tester.getSize(find.byType(DrivesListBody)).width, 1920);
      expect(
        tester.getSize(find.byType(DriveListRow)).width,
        lessThanOrEqualTo(driveListMaxContentWidth),
      );
    });
  });

  group('the words', () {
    /// Every string the page puts on screen, whatever state it is in.
    Future<List<String>> visibleText(
      WidgetTester tester,
      DrivesListState state,
    ) async {
      await pumpBody(tester, state);

      return tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? text.textSpan?.toPlainText())
          .whereType<String>()
          .toList();
    }

    testWidgets('the page never speaks in the first person', (tester) async {
      // The app is not a person and has no colleagues. "We could not reach the
      // network" and "open one and we will fetch just that drive" both said
      // otherwise on the first screen a login sees.
      final firstPerson = RegExp(
        r"\b(we|us|our|ours|we'?ll|we'?re|we'?ve)\b",
        caseSensitive: false,
      );

      for (final state in <DrivesListState>[
        const DrivesListLoading(),
        DrivesListUnavailable(),
        DrivesListLoaded(
          drives: [drive(id: 'a', name: 'Photos', hasBeenWalked: false)],
        ),
        DrivesListLoaded(drives: [drive(id: 'b', name: 'Docs')]),
      ]) {
        for (final text in await visibleText(tester, state)) {
          expect(
            firstPerson.hasMatch(text),
            isFalse,
            reason: '"$text" (${state.runtimeType})',
          );
        }
      }
    });

    testWidgets('the heading stands on its own', (tester) async {
      // A heading that needs a paragraph under it to explain a list of drives
      // was the wrong heading - and the paragraph it had stopped being true
      // the moment opening a drive became the act that fetches it.
      await pumpBody(
        tester,
        DrivesListLoaded(drives: [drive(id: 'a', name: 'Photos')]),
      );

      expect(find.text('Your Drives'), findsOneWidget);
      expect(
        find.text(
          'Choose a drive to open it. Nothing here has been fetched from the '
          'network.',
        ),
        findsNothing,
      );
    });

    testWidgets('the offer says what each of its two ways out does',
        (tester) async {
      await pumpBody(
        tester,
        DrivesListLoaded(
          drives: [drive(id: 'a', name: 'Photos', hasBeenWalked: false)],
        ),
      );

      expect(
        find.text(
          'Your drives are listed, but their contents have not been fetched '
          'yet. Sync them all now, or open one to fetch just that drive.',
        ),
        findsOneWidget,
      );
    });
  });

  /// A scope that filters to nothing is not an empty account. The wallet has
  /// drives, just none of this kind - and the action that would fill the scope
  /// belongs on the screen that says it is empty. Shared is the sharp case:
  /// attaching is the only way a drive gets there.
  group('a scope with nothing in it', () {
    testWidgets('says so, without claiming the account is empty',
        (tester) async {
      await pumpBody(
        tester,
        const DrivesListLoaded(drives: [], scope: DriveScope.private),
      );

      expect(find.text('No private drives yet'), findsOneWidget);
      expect(find.text('Getting Started'), findsNothing,
          reason: 'that is the account with no drives at all, not this');
    });

    testWidgets('and Shared offers the one thing that fills it',
        (tester) async {
      await pumpBody(
        tester,
        const DrivesListLoaded(drives: [], scope: DriveScope.sharedWithMe),
      );

      expect(find.text('No drives shared with you'), findsOneWidget);
      expect(find.text('Attach Drive'), findsOneWidget);
    });

    testWidgets('while the others do not offer attaching', (tester) async {
      await pumpBody(
        tester,
        const DrivesListLoaded(drives: [], scope: DriveScope.public),
      );

      expect(find.text('Attach Drive'), findsNothing);
    });
  });
}
