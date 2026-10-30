import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/domain/drive_list_sort.dart';
import 'package:ardrive/drives_list/presentation/drive_list_row.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/drives_list/presentation/drives_list_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Your drives at the widths between a phone and a wide monitor.
///
/// The list drew cards wherever its five columns did not fit, and cards have
/// no checkboxes, headings or sorting. With the sidebar open that was every
/// window from 950 to about 1120px wide, while a narrower window without the
/// sidebar kept the table: a wider window offered less. It now draws three
/// columns (name, last synced, size) wherever five do not fit and three do.
void main() {
  /// The width the list gets in a window this wide with the sidebar open:
  /// the window less the 240px sidebar, its 1px border, a 16px spacer and
  /// 16px of page padding.
  double besideSidebar(double window) => window - 273;

  DriveListItem drive(String id, String name) => DriveListItem(
        id: id,
        name: name,
        isPrivate: false,
        isSharedWithMe: false,
        isHidden: false,
        dateCreated: DateTime(2024, 3, 4),
        hasBeenWalked: true,
        fileCount: 2,
        totalSize: 100,
        lastSyncedAt: DateTime.now(),
        isSyncing: false,
        lastSyncFailed: false,
      );

  late List<String> ticked;
  late List<DriveListSort> sorted;

  setUp(() {
    ticked = [];
    sorted = [];
  });

  Future<void> pumpList(
    WidgetTester tester, {
    required double width,
    Set<String> selected = const {},
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
              state: DrivesListLoaded(
                drives: [drive('a', 'Photos'), drive('b', 'Work')],
                selected: selected,
              ),
              onOpenDrive: (_) {},
              onTryAgain: () {},
              onSort: sorted.add,
              onToggleSelected: ticked.add,
              onToggleSelectAll: () {},
              onClearSelection: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // The widths the decision on the issue names, with the sidebar open, and
  // 800 without it.
  final midWidths = {
    '950 with the sidebar': besideSidebar(950),
    '1000 with the sidebar': besideSidebar(1000),
    '1100 with the sidebar': besideSidebar(1100),
    '800 without the sidebar': 800.0,
  };

  for (final MapEntry(key: label, value: width) in midWidths.entries) {
    group('at $label', () {
      testWidgets('has three columns, with headings and checkboxes',
          (tester) async {
        // The checkboxes show once the reader is choosing several drives:
        // here, once one is ticked.
        await pumpList(tester, width: width, selected: {'a'});

        expect(find.byType(DriveListHeader), findsOneWidget);
        expect(find.text('Name'), findsOneWidget);
        expect(find.text('Last synced'), findsOneWidget);
        expect(find.text('Size'), findsOneWidget);
        // In a drive's details instead.
        expect(find.text('Files'), findsNothing);
        expect(find.text('Date created'), findsNothing);
        // One per row and the select-all box.
        expect(find.byType(ArDriveCheckBox), findsNWidgets(3));
        expect(tester.takeException(), isNull);
      });

      testWidgets('ticks drives, and the heading says how many',
          (tester) async {
        await pumpList(tester, width: width);

        // Holding the multi-select key shows them all, as in the explorer:
        // Ctrl here (the test platform is not macOS or iOS).
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        await tester.tap(find.byType(ArDriveCheckBox).at(1));
        await tester.pump();
        expect(ticked, ['a']);

        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        // The list as it is once two are ticked. Syncing them is the page's
        // sync button, which reads "Sync 2 selected" by then - see
        // drives_sync_menu_test.dart.
        await pumpList(tester, width: width, selected: {'a', 'b'});

        expect(find.text('2 drives selected'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('sorts by a heading', (tester) async {
        await pumpList(tester, width: width);

        await tester.tap(find.text('Size'));
        await tester.pump();

        expect(sorted, [DriveListSort.size]);
      });
    });
  }

  /// A wider window never offers less than a narrower one.
  testWidgets('every width from 628 to 1920 keeps the checkboxes',
      (tester) async {
    for (var window = 628.0; window <= 1920; window += 36) {
      for (final width in {window, besideSidebar(window)}) {
        if (width < 628) continue;
        await pumpList(tester, width: width, selected: {'a'});

        expect(
          find.byType(ArDriveCheckBox),
          findsNWidgets(3),
          reason: 'a list ${width.toInt()}px wide',
        );
      }
    }
  });

  testWidgets('below 628px the cards are unchanged', (tester) async {
    await pumpList(tester, width: 600, selected: {'a'});

    expect(find.byType(DriveListHeader), findsNothing);
    expect(find.byType(ArDriveCheckBox), findsNothing);
    expect(find.byType(DriveListRow), findsNWidgets(2));
  });

  testWidgets('at 1920 the five columns are unchanged', (tester) async {
    await pumpList(tester, width: besideSidebar(1920), selected: {'a'});

    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Date created'), findsOneWidget);
    expect(find.byType(ArDriveCheckBox), findsNWidgets(3));
  });
}
