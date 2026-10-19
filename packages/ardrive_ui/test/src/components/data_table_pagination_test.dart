import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Row extends IndexedItem {
  const _Row(super.index);

  String get name => 'row $index';

  @override
  List<Object?> get props => [index];
}

List<_Row> _rows(int count) => List.generate(count, _Row.new);

void main() {
  group('paginationSlots', () {
    test('lists every page when they all fit', () {
      expect(paginationSlots(0, 1), [0]);
      expect(paginationSlots(3, 7), [0, 1, 2, 3, 4, 5, 6]);
    });

    test('keeps the first and last page and the pages beside the current', () {
      expect(paginationSlots(0, 20), [0, 1, 2, 3, 4, null, 19]);
      expect(paginationSlots(10, 20), [0, null, 9, 10, 11, null, 19]);
      expect(paginationSlots(19, 20), [0, null, 15, 16, 17, 18, 19]);
    });

    // A gap of one page is that page, not an ellipsis standing in for it.
    test('never hides a single page behind an ellipsis', () {
      expect(paginationSlots(3, 8), [0, 1, 2, 3, 4, null, 7]);
      expect(paginationSlots(4, 8), [0, null, 3, 4, 5, 6, 7]);
    });

    test('always has the same number of slots, so nothing moves', () {
      for (var page = 0; page < 40; page++) {
        final slots = paginationSlots(page, 40);
        expect(slots, hasLength(7), reason: 'page $page');
        expect(slots, contains(page));
        expect(slots.first, 0);
        expect(slots.last, 39);
      }
      for (var page = 0; page < 40; page++) {
        expect(paginationSlots(page, 40, siblings: 0), hasLength(5));
      }
    });
  });

  group('ArDriveDataTable pagination', () {
    late List<int> pagesReported;
    late List<int> sizesReported;
    late List<String> reports;
    late List<_Row> rowsOpened;
    late List<double> offsetsSaved;

    setUp(() {
      pagesReported = [];
      sizesReported = [];
      reports = [];
      rowsOpened = [];
      offsetsSaved = [];
    });

    Future<void> pumpTable(
      WidgetTester tester, {
      required int rows,
      double width = 1200,
      double height = 900,
      double textScale = 1,
      int? rowsPerPage,
      int? initialPage,
      _Row? revealRow,
      bool? sizeColumnVisible,
      List<TableColumn>? columns,
      Key? tableKey,
    }) async {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ArDriveApp(
          builder: (context) => MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, height),
                textScaler: TextScaler.linear(textScale),
              ),
              child: Scaffold(
                body: ArDriveDataTable<_Row>(
                  key: tableKey,
                  columns: columns ??
                      [
                        TableColumn('Name', 1, index: 0),
                        if (sizeColumnVisible != null)
                          TableColumn(
                            'Size',
                            1,
                            index: 1,
                            isVisible: sizeColumnVisible,
                          ),
                      ],
                  rows: _rows(rows),
                  buildRow: (row) => TableRowWidget([
                    Text(row.name),
                    if (sizeColumnVisible != null) Text('size ${row.index}'),
                  ]),
                  rowsPerPageText: 'Rows per page',
                  rowsPerPage: rowsPerPage,
                  initialPage: initialPage,
                  revealRow: revealRow,
                  onChangePage: (page) {
                    pagesReported.add(page);
                    reports.add('page $page');
                  },
                  onRowsPerPageChanged: (size) {
                    sizesReported.add(size);
                    reports.add('size $size');
                  },
                  onChangeMultiSelecting: (_) {},
                  onRowOpen: rowsOpened.add,
                  onScrollOffsetSaved: offsetsSaved.add,
                  sortRows: (list, column, order) => order == TableSort.asc
                      ? (list.toList()
                        ..sort((a, b) => a.index.compareTo(b.index)))
                      : (list.toList()
                        ..sort((a, b) => b.index.compareTo(a.index))),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String range(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('pagination-range')))
        .data!;

    Finder button(String key) => find.byKey(ValueKey(key));

    ScrollPosition listPosition(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ArDriveDataTable<_Row>),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

    testWidgets('has no footer when every row fits on the smallest page',
        (tester) async {
      await pumpTable(tester, rows: 25);

      expect(find.byType(PaginationFooter), findsNothing);
      expect(find.text('row 24'), findsOneWidget);
    });

    testWidgets('says which rows are on screen, and pages through them',
        (tester) async {
      await pumpTable(tester, rows: 60);

      expect(range(tester), '1-25 of 60');

      await tester.tap(button('pagination-next'));
      await tester.pumpAndSettle();
      expect(range(tester), '26-50 of 60');
      expect(find.text('row 25'), findsOneWidget);
      expect(pagesReported, [1]);

      await tester.tap(button('pagination-page-2'));
      await tester.pumpAndSettle();
      expect(range(tester), '51-60 of 60');

      // The last page: next does nothing.
      await tester.tap(button('pagination-next'));
      await tester.pumpAndSettle();
      expect(range(tester), '51-60 of 60');
      expect(pagesReported, [1, 2]);

      await tester.tap(button('pagination-previous'));
      await tester.pumpAndSettle();
      expect(range(tester), '26-50 of 60');
    });

    testWidgets('a new page starts at its top', (tester) async {
      await pumpTable(tester, rows: 60, height: 400);

      listPosition(tester).jumpTo(listPosition(tester).maxScrollExtent);
      await tester.pump();
      expect(listPosition(tester).pixels, greaterThan(0));

      await tester.tap(button('pagination-next'));
      await tester.pumpAndSettle();

      expect(listPosition(tester).pixels, 0);
    });

    testWidgets('changing rows per page keeps the first row in view',
        (tester) async {
      await pumpTable(tester, rows: 120);

      await tester.tap(button('pagination-page-2'));
      await tester.pumpAndSettle();
      expect(range(tester), '51-75 of 120');

      await tester.tap(button('rows-per-page'));
      await tester.pumpAndSettle();
      await tester.tap(button('rows-per-page-50'));
      await tester.pumpAndSettle();

      expect(sizesReported, [50]);
      expect(range(tester), '51-100 of 120');
      // The size first: a listener keeping the page as a row needs it to
      // turn the page that follows into one.
      expect(reports.sublist(reports.length - 2), ['size 50', 'page 1']);
    });

    testWidgets('a size passed in later is applied', (tester) async {
      await pumpTable(tester, rows: 120);
      await pumpTable(tester, rows: 120, rowsPerPage: 100);

      expect(range(tester), '1-100 of 120');
    });

    testWidgets('keeps the footer, without pages, when one page holds all',
        (tester) async {
      await pumpTable(tester, rows: 40, rowsPerPage: 50);

      expect(range(tester), '1-40 of 40');
      expect(button('rows-per-page'), findsOneWidget);
      expect(button('pagination-next'), findsNothing);
    });

    testWidgets('a page past the end opens the last page instead',
        (tester) async {
      await pumpTable(tester, rows: 30, initialPage: 9);

      expect(tester.takeException(), isNull);
      expect(range(tester), '26-30 of 30');
    });

    testWidgets('opens on the page holding the row it is asked to show',
        (tester) async {
      await pumpTable(tester, rows: 60, revealRow: const _Row(55));

      expect(range(tester), '51-60 of 60');
      expect(find.text('row 55'), findsOneWidget);
      expect(pagesReported, [2]);
    });

    testWidgets('scrolls a revealed row below the fold into view',
        (tester) async {
      await pumpTable(
        tester,
        rows: 60,
        height: 400,
        revealRow: const _Row(48),
      );

      expect(range(tester), '26-50 of 60');
      final row = tester.getRect(find.text('row 48'));
      final list = tester.getRect(
        find
            .descendant(
              of: find.byType(ArDriveDataTable<_Row>),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(list.top <= row.top && row.bottom <= list.bottom, isTrue,
          reason: 'row 48 at $row, list at $list');
    });

    // The caller hides columns as the table narrows. The table used to read
    // them once, so its rows kept every cell and squeezed them to a letter.
    testWidgets('follows the caller when a column is hidden', (tester) async {
      await pumpTable(tester, rows: 10, sizeColumnVisible: true);
      expect(find.text('size 3'), findsOneWidget);

      await pumpTable(tester, rows: 10, sizeColumnVisible: false);
      expect(find.text('size 3'), findsNothing);
      expect(find.text('row 3'), findsOneWidget);
    });

    // A caller that does not pass the reader's choice back, such as the
    // storybook, rebuilt the table with the column showing again.
    testWidgets('keeps a column the reader hid when the caller rebuilds',
        (tester) async {
      await pumpTable(tester, rows: 10, sizeColumnVisible: true);

      await tester.tap(find.byType(ArDriveSubmenu));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ArDriveCheckBox, 'Size'));
      await tester.pumpAndSettle();
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.text('size 3'), findsNothing);

      await pumpTable(tester, rows: 10, sizeColumnVisible: true);
      expect(find.text('size 3'), findsNothing);
    });

    testWidgets('follows a caller that changes its column list in place',
        (tester) async {
      final columns = [
        TableColumn('Name', 1, index: 0),
        TableColumn('Size', 1, index: 1),
      ];
      await pumpTable(
        tester,
        rows: 10,
        sizeColumnVisible: true,
        columns: columns,
      );
      expect(find.text('size 3'), findsOneWidget);

      columns[1] = TableColumn('Size', 1, index: 1, isVisible: false);
      await pumpTable(
        tester,
        rows: 10,
        sizeColumnVisible: true,
        columns: columns,
      );
      expect(find.text('size 3'), findsNothing);
    });

    // A table rebuilt in place, as after a sync, is built before the old one
    // is taken down, so the offset must be known before then.
    testWidgets('reports how far the list is scrolled as it scrolls',
        (tester) async {
      await pumpTable(tester, rows: 100, rowsPerPage: 100, height: 400);

      await tester.drag(find.text('row 2'), const Offset(0, -300));
      await tester.pumpAndSettle();

      final offset = listPosition(tester).pixels;
      expect(offset, greaterThan(0));
      expect(offsetsSaved.last, offset);
    });

    testWidgets('a menu opened with the pointer does not take focus',
        (tester) async {
      await pumpTable(tester, rows: 120);

      await tester.tap(button('rows-per-page'));
      await tester.pumpAndSettle();

      expect(button('rows-per-page-50'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot(startsWith('rows per page')),
      );
    });

    testWidgets('sorting goes back to the first page', (tester) async {
      await pumpTable(tester, rows: 60);
      await tester.tap(button('pagination-page-2'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();

      expect(range(tester), '1-25 of 60');
    });

    testWidgets('is worked from the keyboard, without opening a row',
        (tester) async {
      await pumpTable(tester, rows: 60);

      // A row is selected, so Enter on the table itself would open it.
      await tester.tap(find.text('row 3'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle(kDoubleTapTimeout);

      Focus.of(
        tester.element(
          find.descendant(
            of: button('pagination-next'),
            matching: find.byType(GestureDetector),
          ),
        ),
      ).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(range(tester), '26-50 of 60');

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(range(tester), '51-60 of 60');

      expect(rowsOpened, isEmpty);
    });

    testWidgets('chooses rows per page from the keyboard', (tester) async {
      await pumpTable(tester, rows: 120);

      Focus.of(
        tester.element(
          find.descendant(
            of: button('rows-per-page'),
            matching: find.byType(GestureDetector),
          ),
        ),
      ).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(button('rows-per-page-100'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'rows per page 25',
        reason: 'opened from the keyboard, the menu focuses the current size',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(sizesReported, [50]);
      expect(range(tester), '1-50 of 120');
    });

    // A menu opened with the pointer has no focus inside it, so it does not
    // hear Escape for itself.
    testWidgets('Escape closes a menu opened with the pointer', (tester) async {
      await pumpTable(tester, rows: 120);

      await tester.tap(button('rows-per-page'));
      await tester.pumpAndSettle();
      expect(button('rows-per-page-50'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(button('rows-per-page-50'), findsNothing);
    });

    // Nine pages, so every number is one digit: the test font draws digits
    // far wider than the app's, and two would outgrow a button here only.
    testWidgets('the pager keeps its width as the pages it shows change',
        (tester) async {
      final widths = <double>{};
      for (final page in [0, 4, 8]) {
        // A new table each time: initialPage is read when one is built.
        await pumpTable(
          tester,
          rows: 225,
          initialPage: page,
          tableKey: ValueKey(page),
        );
        expect(button('pagination-page-$page'), findsOneWidget);
        final previous = tester.getRect(button('pagination-previous'));
        final next = tester.getRect(button('pagination-next'));
        widths.add(next.right - previous.left);
      }

      // Page 0 shows one ellipsis, page 4 two, page 8 one.
      expect(widths, hasLength(1), reason: '$widths');
    });

    testWidgets('names its controls for a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpTable(tester, rows: 60);

      expect(
        tester.getSemantics(button('pagination-next')),
        containsSemantics(
          label: 'Next page',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(button('pagination-previous')),
        containsSemantics(label: 'Previous page', isEnabled: false),
      );
      expect(
        tester.getSemantics(button('pagination-page-0')),
        containsSemantics(label: 'Page 1', isSelected: true),
      );
      expect(
        tester.getSemantics(button('rows-per-page')),
        containsSemantics(label: 'Rows per page: 25', isButton: true),
      );
      semantics.dispose();
    });

    // The footer gives way as the table narrows; it must never overflow.
    for (final width in [1400.0, 900.0, 700.0, 640.0, 560.0, 450.0, 320.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('fits at $width px, text scale $scale', (tester) async {
          await pumpTable(
            tester,
            rows: 5000,
            width: width,
            textScale: scale,
            initialPage: 100,
          );

          expect(tester.takeException(), isNull);
          expect(find.byType(PaginationFooter), findsOneWidget);
          expect(button('pagination-next'), findsOneWidget);

          final footer = tester.getRect(find.byType(PaginationFooter));
          for (final key in ['pagination-next', 'pagination-previous']) {
            final rect = tester.getRect(button(key));
            expect(footer.contains(rect.topLeft), isTrue, reason: key);
            expect(
                footer.contains(rect.bottomRight - const Offset(1, 1)), isTrue,
                reason: key);
          }
        });
      }
    }

    testWidgets('drops the picker, then the page numbers, as it narrows',
        (tester) async {
      await pumpTable(tester, rows: 300, width: 1200);
      expect(button('rows-per-page'), findsOneWidget);
      expect(button('pagination-page-1'), findsOneWidget);

      await pumpTable(tester, rows: 300, width: 560);
      expect(button('rows-per-page'), findsNothing);
      expect(button('pagination-page-1'), findsOneWidget);

      await pumpTable(tester, rows: 300, width: 400);
      expect(button('pagination-page-1'), findsNothing);
      expect(range(tester), '1-25 of 300');
    });

    /// A folder being synced hands the table a longer list on every batch,
    /// in the order the database returns it. The order the reader chose from
    /// a column header has to survive that.
    testWidgets('keeps a header sort when rows are added', (tester) async {
      List<String> namesInOrder() {
        final texts = find.textContaining(RegExp(r'^row \d+$'));
        final found = tester.widgetList<Text>(texts).toList();
        final ys = [
          for (var i = 0; i < found.length; i++)
            tester.getTopLeft(texts.at(i)).dy,
        ];
        final order = List.generate(found.length, (i) => i)
          ..sort((a, b) => ys[a].compareTo(ys[b]));
        return [for (final i in order) found[i].data!];
      }

      await pumpTable(tester, rows: 3);

      // Ascending, then descending.
      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();
      expect(namesInOrder(), ['row 2', 'row 1', 'row 0']);

      await pumpTable(tester, rows: 4);

      expect(namesInOrder(), ['row 3', 'row 2', 'row 1', 'row 0']);
    });
  });
}
