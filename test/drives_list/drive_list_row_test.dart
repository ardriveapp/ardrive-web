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
    bool hasBeenWalked = true,
    int? itemCount = 3,
    int? totalSize = 350,
    DateTime? lastSyncedAt,
    bool isSyncing = false,
  }) =>
      DriveListItem(
        id: 'drive-id',
        name: name,
        isPrivate: isPrivate,
        isSharedWithMe: isSharedWithMe,
        dateCreated: DateTime(2024, 3, 4),
        hasBeenWalked: hasBeenWalked,
        itemCount: hasBeenWalked ? itemCount : null,
        totalSize: hasBeenWalked ? totalSize : null,
        lastSyncedAt: lastSyncedAt,
        isSyncing: isSyncing,
      );

  Widget rowUnder(
    DriveListItem item, {
    required double width,
    required bool showsColumns,
    bool dark = false,
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
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: DriveListRow(
                drive: item,
                showsColumns: showsColumns,
                onTap: onTap ?? () {},
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
        onTap: onTap,
      ),
    );
  }

  group('what the row says', () {
    testWidgets('a drive nothing has looked at reports no count and no size',
        (tester) async {
      await pumpRow(tester, drive(hasBeenWalked: false), width: 1200);

      expect(find.text('Never synced'), findsOneWidget);
      // Two withheld figures - items and size - and not a single zero.
      expect(find.text(driveListWithheldFigure), findsNWidgets(2));
      expect(find.text('No items'), findsNothing);
      expect(find.text('0 B'), findsNothing);
    });

    testWidgets('a walked drive reports both', (tester) async {
      await pumpRow(tester, drive(), width: 1200);

      expect(find.text('3 items'), findsOneWidget);
      expect(find.text('350 B'), findsOneWidget);
      expect(find.text(driveListWithheldFigure), findsNothing);
    });

    testWidgets('one item is one item, not "1 items"', (tester) async {
      await pumpRow(tester, drive(itemCount: 1), width: 1200);

      expect(find.text('1 item'), findsOneWidget);
    });

    testWidgets('a walked drive that is genuinely empty says so',
        (tester) async {
      await pumpRow(tester, drive(itemCount: 0, totalSize: 0), width: 1200);

      // The difference between this and the row above is the whole point of
      // the page: "No items" is a finding, the mark is an admission.
      expect(find.text('No items'), findsOneWidget);
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

      expect(find.text('3 items'), findsOneWidget);
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
      final itemsX = tester.getTopLeft(find.text('3 items')).dx;

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
          lastSyncedAt: DateTime.now().subtract(const Duration(days: 3)),
          itemCount: 123456,
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
}
