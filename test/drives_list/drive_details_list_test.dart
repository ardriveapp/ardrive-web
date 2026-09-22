import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/presentation/drive_list_row.dart';
import 'package:ardrive/drives_list/presentation/drives_list_page.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

DriveListItem _drive(String id, String name) => DriveListItem(
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

/// Your Drives with a drive's details beside it.
///
/// A click on a drive opens its details, as a click on a row does in the
/// explorer; a double-click still opens the drive. While the details push the
/// list narrower it keeps its rows as rows, dropping to three columns, because
/// a card is taller than a row and would move every row under the pointer.
void main() {
  final twoDrives = DrivesListLoaded(
    drives: [_drive('a', 'Photos'), _drive('b', 'Work')],
  );

  late List<String> chosen;
  late List<String> opened;

  setUp(() {
    chosen = [];
    opened = [];
  });

  Future<void> pumpList(
    WidgetTester tester, {
    String? chosenDriveId,
    bool allowCompactColumns = false,
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
              state: twoDrives,
              onOpenDrive: (drive) => opened.add(drive.id),
              onTryAgain: () {},
              onSyncAllDrives: () {},
              chosenDriveId: chosenDriveId,
              onChoose: chosen.add,
              allowCompactColumns: allowCompactColumns,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    return gesture;
  }

  Future<void> click(
      WidgetTester tester, TestGesture pointer, String name) async {
    await pointer.down(tester.getCenter(find.text(name)));
    await pointer.up();
    await tester.pump();
  }

  Future<void> waitOutDoubleClick(WidgetTester tester) =>
      tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

  final chosenColour = lightTheme().tableTheme.selectedItemColor;
  Finder drawnChosen(String name) => find.ancestor(
        of: find.text(name),
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == chosenColour,
        ),
      );

  testWidgets('a click shows that drive its details', (tester) async {
    await pumpList(tester);
    final pointer = await mouse(tester);

    await click(tester, pointer, 'Work');
    await waitOutDoubleClick(tester);

    expect(chosen, contains('b'));
    expect(opened, isEmpty);
  });

  testWidgets('and a double-click still opens it', (tester) async {
    await pumpList(tester);
    final pointer = await mouse(tester);

    await click(tester, pointer, 'Work');
    await tester.pump(const Duration(milliseconds: 100));
    await click(tester, pointer, 'Work');

    expect(opened, ['b']);
  });

  testWidgets('the drive whose details are open is drawn chosen',
      (tester) async {
    await pumpList(tester, chosenDriveId: 'b');

    expect(drawnChosen('Work'), findsOneWidget);
    expect(drawnChosen('Photos'), findsNothing);
  });

  /// Closing the details leaves focus on the row. A click there changes no
  /// focus, and must still bring them back.
  testWidgets('clicking the row whose details were closed reopens them',
      (tester) async {
    await pumpList(tester);
    final pointer = await mouse(tester);

    await click(tester, pointer, 'Work');
    await waitOutDoubleClick(tester);
    chosen.clear();

    await click(tester, pointer, 'Work');
    await waitOutDoubleClick(tester);

    expect(chosen, contains('b'));
  });

  group('beside the details', () {
    // Wide enough for three columns and not five.
    const narrowed = 700.0;

    testWidgets('keeps its rows, as three columns', (tester) async {
      await pumpList(
        tester,
        width: narrowed,
        chosenDriveId: 'b',
        allowCompactColumns: true,
      );

      expect(find.byType(DriveListHeader), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('Files'), findsNothing);
      expect(find.text('Date created'), findsNothing);
    });

    /// Without the details, the list's own breakpoints are untouched: at this
    /// width it is cards, as it always was.
    testWidgets('and only there', (tester) async {
      await pumpList(tester, width: narrowed);

      expect(find.byType(DriveListHeader), findsNothing);
    });
  });

  /// Push or cover, at the window widths people actually have.
  ///
  /// The page area is the window less the expanded sidebar (240) and the
  /// page's right padding (16); the panel is the explorer's, a quarter of the
  /// window and never under 375.
  group('the details push the list', () {
    bool pushesAt(double window) => driveDetailsPushList(
          width: window - 240 - 16,
          panelWidth: window * 0.25 < 375 ? 375 : window * 0.25,
        );

    test('on a wide monitor, keeping all five columns', () {
      expect(pushesAt(1920), isTrue);
      expect(driveListShowsColumns(1920 - 240 - 16 - 480), isTrue);
    });

    test('on a laptop, dropping to three', () {
      expect(pushesAt(1440), isTrue);
      expect(pushesAt(1280), isTrue);
      expect(driveListShowsColumns(1440 - 240 - 16 - 375), isFalse);
    });

    /// Three columns will not fit beside the panel, and cards would move
    /// every row.
    test('but cover it where the rows would become cards', () {
      expect(pushesAt(1200), isFalse);
    });

    test('and cover a list that is cards already', () {
      expect(pushesAt(1100), isFalse);
    });
  });
}
