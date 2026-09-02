import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/presentation/drive_list_row.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// One row of the drives list, at the widths and in the themes it actually
/// ships in.
///
/// The row is where every honesty rule in this page lands: a drive nothing has
/// looked at must not report a count, a drive that was walked by an older
/// build must not be given a time it never had, and neither the phone nor the
/// desktop layout is allowed to be the other one squeezed.
void main() {
  DriveListItem drive({
    String name = 'Photos',
    bool isPrivate = false,
    bool isSharedWithMe = false,
    bool isHidden = false,
    bool hasBeenWalked = true,
    int? fileCount = 3,
    int? totalSize = 350,
    DateTime? lastSyncedAt,
    bool isSyncing = false,
    bool lastSyncFailed = false,
  }) =>
      DriveListItem(
        id: 'drive-id',
        name: name,
        isPrivate: isPrivate,
        isSharedWithMe: isSharedWithMe,
        isHidden: isHidden,
        dateCreated: DateTime(2024, 3, 4),
        hasBeenWalked: hasBeenWalked,
        fileCount: hasBeenWalked ? fileCount : null,
        totalSize: hasBeenWalked ? totalSize : null,
        lastSyncedAt: lastSyncedAt,
        isSyncing: isSyncing,
        lastSyncFailed: lastSyncFailed,
      );

  Widget rowUnder(
    DriveListItem item, {
    required double width,
    required bool showsColumns,
    bool dark = false,
    bool withHeader = false,
    double textScale = 1,
    VoidCallback? onTap,
  }) {
    return ArDriveTheme(
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
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              // The headings share the row's flex constants, so a test about
              // what a column is called has to render the pair the page
              // renders.
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (withHeader) const DriveListHeader(),
                  DriveListRow(
                    drive: item,
                    showsColumns: showsColumns,
                    onTap: onTap ?? () {},
                  ),
                ],
              ),
            ),
          ),
        ),
          ),
        ),
      ),
    );
  }

  /// Renders the row at exactly [width].
  ///
  /// The surface is grown to fit rather than left at the 800px default,
  /// because a "desktop width" that silently gets clamped to 800 is not a
  /// desktop width - and a test that renders the same branch twice under two
  /// names is how this series has already fooled itself once.
  Future<void> pumpRow(
    WidgetTester tester,
    DriveListItem item, {
    required double width,
    bool? showsColumns,
    bool dark = false,
    bool withHeader = false,
    double textScale = 1,
    VoidCallback? onTap,
  }) async {
    await tester.binding.setSurfaceSize(Size(width + 200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      rowUnder(
        item,
        width: width,
        // What the page would decide for a list this wide. The row is told;
        // it no longer works it out for itself.
        showsColumns: showsColumns ?? driveListShowsColumns(width),
        dark: dark,
        withHeader: withHeader,
        textScale: textScale,
        onTap: onTap,
      ),
    );
  }

  /// One word, one meaning, on surfaces the user sees together.
  ///
  /// This column counts file rows and nothing else, while the sync counts a
  /// folder as an item and says so on the same screen - so a drive holding
  /// three folders and two files reported "Found 5 items so far...", then "5
  /// items changed", above a row reading "2 items". Three numbers, one word,
  /// all correct under their own definition and irreconcilable side by side.
  ///
  /// The definition kept is the sync's, because a running count that ignores
  /// folders sits at zero while a drive of folders streams in. The column
  /// therefore says what it actually counts.
  group('items and files are not the same word', () {
    testWidgets('the column of file counts is headed "Files"', (tester) async {
      await pumpRow(tester, drive(), width: 1200, withHeader: true);

      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Items'), findsNothing,
          reason: 'this column does not count folders, and the sync does');
    });

    testWidgets('and no row puts a files-only figure under the word "item"',
        (tester) async {
      for (final count in [0, 1, 3, 128456]) {
        await pumpRow(tester, drive(fileCount: count), width: 1200);

        expect(
          find.textContaining('item'),
          findsNothing,
          reason: 'a file count called "$count items" is the number the sync '
              'reports under the same word, and it is a different number',
        );
      }
    });
  });

  group('what the row says', () {
    testWidgets('a drive nothing has looked at reports no count and no size',
        (tester) async {
      await pumpRow(tester, drive(hasBeenWalked: false), width: 1200);

      expect(find.text('Never synced'), findsOneWidget);
      // Two withheld figures - items and size - and not a single zero.
      expect(find.text(driveListWithheldFigure), findsNWidgets(2));
      expect(find.text('No files'), findsNothing);
      expect(find.text('0 B'), findsNothing);
    });

    testWidgets('a walked drive reports both', (tester) async {
      await pumpRow(tester, drive(), width: 1200);

      expect(find.text('3 files'), findsOneWidget);
      expect(find.text('350 B'), findsOneWidget);
      expect(find.text(driveListWithheldFigure), findsNothing);
    });

    testWidgets('one file is one file, not "1 files"', (tester) async {
      await pumpRow(tester, drive(fileCount: 1), width: 1200);

      expect(find.text('1 file'), findsOneWidget);
    });

    testWidgets('a walked drive that is genuinely empty says so',
        (tester) async {
      await pumpRow(tester, drive(fileCount: 0, totalSize: 0), width: 1200);

      // The difference between this and the row above is the whole point of
      // the page: "No files" is a finding, the mark is an admission.
      expect(find.text('No files'), findsOneWidget);
      expect(find.text(driveListWithheldFigure), findsNothing);
    });

    testWidgets(
        'a drive walked by an older build is not given a time it never '
        'had', (tester) async {
      await pumpRow(tester, drive(lastSyncedAt: null), width: 1200);

      expect(find.text('Synced'), findsOneWidget);
      expect(find.text('Never synced'), findsNothing);
    });

    testWidgets('a recorded time is reported as one', (tester) async {
      await pumpRow(
        tester,
        drive(lastSyncedAt: DateTime.now().subtract(const Duration(hours: 2))),
        width: 1200,
      );

      expect(find.text('Synced 2 hours ago'), findsOneWidget);
    });

    testWidgets('a running sync outranks whatever was recorded before it',
        (tester) async {
      await pumpRow(
        tester,
        drive(
          isSyncing: true,
          lastSyncFailed: false,
          lastSyncedAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        width: 1200,
      );

      expect(find.text('Syncing...'), findsOneWidget);
      expect(find.text('Synced 2 hours ago'), findsNothing);
    });

    testWidgets('a drive somebody else owns is marked in place',
        (tester) async {
      await pumpRow(tester, drive(isSharedWithMe: true), width: 1200);

      expect(find.text('Shared with me'), findsOneWidget);
    });

    testWidgets('a drive the user owns carries no such marker', (tester) async {
      await pumpRow(tester, drive(), width: 1200);

      expect(find.text('Shared with me'), findsNothing);
    });

    testWidgets('opening one is what the tap does', (tester) async {
      var opened = 0;

      await pumpRow(tester, drive(), width: 1200, onTap: () => opened++);
      await tester.tap(find.text('Photos'));

      expect(opened, 1);
    });
  });

  group('the withheld figures', () {
    testWidgets('are drawn in a character the brand font actually has',
        (tester) async {
      // Wavehaus contains no em dash, no en dash and no ellipsis - its cmap
      // was checked. An em dash here renders out of the brand face in
      // whatever the fallback happens to be, which on a table of dashes is
      // the most visible text on the page.
      expect(
        driveListWithheldFigure.codeUnits.every((unit) => unit < 128),
        isTrue,
        reason: 'the withheld mark is outside ASCII: $driveListWithheldFigure',
      );
    });

    testWidgets('are left out of the stacked layout, which has no headings',
        (tester) async {
      await pumpRow(
        tester,
        drive(hasBeenWalked: false),
        width: 390,
        showsColumns: false,
      );

      // Two context-free marks under a name, with the heading that would have
      // explained them nowhere on screen and the tooltip that would have
      // explained them unreachable without a mouse.
      expect(find.text(driveListWithheldFigure), findsNothing);
      // The row still says the same thing, in words.
      expect(find.text('Never synced'), findsOneWidget);
    });

    testWidgets('and a walked drive still reports both when stacked',
        (tester) async {
      await pumpRow(tester, drive(), width: 390, showsColumns: false);

      expect(find.text('3 files'), findsOneWidget);
      expect(find.text('350 B'), findsOneWidget);
    });
  });

  group('the two layouts are two layouts', () {
    /// Read off the rendered geometry rather than off a flag: the only proof
    /// that the narrow one is not the wide one squeezed is that the pieces are
    /// stacked.
    ///
    /// Read horizontally: in the stacked layout the item count starts at the
    /// row's left edge, ahead of the name, which is indented past the privacy
    /// icon. In the tabular layout it sits in its own column, far to the
    /// right. Vertical position cannot tell them apart - two texts of
    /// different sizes centred in one row already have different tops.
    bool isStacked(WidgetTester tester) {
      final nameX = tester.getTopLeft(find.text('Photos')).dx;
      final itemsX = tester.getTopLeft(find.text('3 files')).dx;

      return itemsX < nameX;
    }

    testWidgets('it draws the stacked card when told to', (tester) async {
      await pumpRow(tester, drive(), width: 1200, showsColumns: false);

      expect(isStacked(tester), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('and the columns when told that', (tester) async {
      await pumpRow(tester, drive(), width: 320, showsColumns: true);

      expect(isStacked(tester), isFalse);
    });

    testWidgets('320px stacks', (tester) async {
      await pumpRow(tester, drive(), width: 320);

      expect(isStacked(tester), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('390px stacks', (tester) async {
      await pumpRow(tester, drive(), width: 390);

      expect(isStacked(tester), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a desktop width does not', (tester) async {
      await pumpRow(tester, drive(), width: 1200);

      expect(isStacked(tester), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'the narrowest row that draws columns still has room for the one '
        'fact the page is for', (tester) async {
      // The band this is about shipped truncated: "Synced 7 minutes ag...".
      // A layout that draws five columns and then clips the sentence they are
      // there to carry has chosen the table over the content.
      // The row's own padding and the gutter it reserves for the actions
      // menu are both width the columns never see.
      const width = driveListColumnsFrom +
          driveListRowHorizontalPadding * 2 +
          driveListMenuGutter;

      await pumpRow(
        tester,
        drive(
          lastSyncedAt:
              DateTime.now().subtract(const Duration(minutes: 59, seconds: 30)),
        ),
        width: width,
      );

      expect(driveListShowsColumns(width), isTrue);

      final lastSynced = tester.getSize(find.text('Synced 59 minutes ago'));

      expect(
        lastSynced.width,
        greaterThanOrEqualTo(driveListSyncColumnMinimum),
        reason: 'the last-synced column is too narrow to say when',
      );
    });

    testWidgets('320px does not overflow with a long name and every marker',
        (tester) async {
      await pumpRow(
        tester,
        drive(
          name: 'A drive with a deliberately very long name indeed',
          isPrivate: true,
          isSharedWithMe: true,
          isHidden: false,
          lastSyncedAt: DateTime.now().subtract(const Duration(days: 3)),
          fileCount: 123456,
          totalSize: 987654321,
        ),
        width: 320,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('320px does not overflow in the dark theme either',
        (tester) async {
      await pumpRow(
        tester,
        drive(
          name: 'A drive with a deliberately very long name indeed',
          isPrivate: true,
          isSharedWithMe: true,
          isHidden: false,
        ),
        width: 320,
        dark: true,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('a desktop width does not overflow in the dark theme either',
        (tester) async {
      await pumpRow(tester, drive(), width: 1200, dark: true);

      expect(tester.takeException(), isNull);
    });
  });

  /// The name is what says *which* drive this is. It is the last thing that
  /// may be given up for room, and it was the first: the "Shared with me"
  /// badge was a rigid child of the same row, so at 320px the name collapsed
  /// to zero width and disappeared while the badge ran off the screen. Onset
  /// was around 1.1x - ordinary browser zoom.
  ///
  /// This harness had no text-scale knob at all until this was found, which is
  /// why its own "320px does not overflow with every marker" case passed: it
  /// only ever ran at 1.0.
  group('a shared drive keeps its name at every text scale', () {
    for (final scale in [1.0, 1.1, 1.3, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets(
            '320px at ${scale}x in the ${dark ? 'dark' : 'light'} theme',
            (tester) async {
          await pumpRow(
            tester,
            drive(name: 'Family Photos Archive', isSharedWithMe: true),
            width: 320,
            textScale: scale,
            dark: dark,
          );

          expect(tester.takeException(), isNull,
              reason: 'the row overflowed at ${scale}x');

          final name = find.text('Family Photos Archive');
          expect(name, findsOneWidget);
          expect(
            tester.getSize(name).width,
            greaterThan(0),
            reason: 'the drive name was squeezed out of its own row',
          );
        });
      }
    }

    testWidgets('and the badge is still shown, not dropped', (tester) async {
      await pumpRow(
        tester,
        drive(name: 'Family Photos Archive', isSharedWithMe: true),
        width: 320,
        textScale: 2,
      );

      expect(find.text('Shared with me'), findsOneWidget);
    });
  });

  /// The top bar says "1 of 5 drives failed"; this list is where a reader goes
  /// to find out which. Until now every row said either "Never synced" or a
  /// stale timestamp, so the one drive that failed looked exactly like the
  /// four that succeeded - and on a first sync, exactly like one nobody had
  /// opened yet.
  group('a drive that could not be read says so', () {
    testWidgets('instead of the time it last succeeded at', (tester) async {
      await pumpRow(
        tester,
        drive(
          lastSyncedAt: DateTime.now().subtract(const Duration(days: 2)),
          lastSyncFailed: true,
        ),
        width: 1200,
      );

      expect(find.text('Last sync failed'), findsOneWidget);
      expect(find.textContaining('days ago'), findsNothing);
    });

    testWidgets('and is distinguishable from one nobody has opened',
        (tester) async {
      await pumpRow(tester, drive(hasBeenWalked: false), width: 1200);
      expect(find.text('Never synced'), findsOneWidget);
      expect(find.text('Last sync failed'), findsNothing);

      await pumpRow(
        tester,
        drive(hasBeenWalked: false, lastSyncFailed: true),
        width: 1200,
      );
      expect(find.text('Last sync failed'), findsOneWidget);
      expect(find.text('Never synced'), findsNothing);
    });

    testWidgets('but a running sync still wins, since it is happening now',
        (tester) async {
      await pumpRow(
        tester,
        drive(isSyncing: true, lastSyncFailed: true),
        width: 1200,
      );

      expect(find.text('Syncing...'), findsOneWidget);
      expect(find.text('Last sync failed'), findsNothing);
    });
  });
}
