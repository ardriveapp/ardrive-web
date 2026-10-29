import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A row that compares by its id alone, as the app's rows do: a new version
/// of a file is the same row with a different size.
class _Row extends IndexedItem {
  const _Row(super.index, {required this.id, required this.size});

  final String id;
  final int size;

  @override
  List<Object?> get props => [id];
}

/// The fill of the row showing [id]: the row's own box, the one keyed by
/// its row object, whose colour is the row's.
Color rowFill(WidgetTester tester, String id) {
  final box = find
      .ancestor(
        of: find.text(id),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.key is ValueKey<Object> && w.color != null,
        ),
      )
      .first;
  return tester.widget<Container>(box).color!;
}

void main() {
  group('ArDriveDataTable rows', () {
    late StateSetter setRows;
    late List<_Row> rows;
    _Row? selected;

    Future<void> pumpTable(
      WidgetTester tester,
      List<_Row> initial, {
      void Function(_Row row)? onRowOpen,
    }) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      rows = initial;
      selected = null;

      await tester.pumpWidget(
        ArDriveApp(
          builder: (context) => MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  setRows = setState;

                  return ArDriveDataTable<_Row>(
                    columns: [
                      TableColumn('Name', 1, index: 0),
                      TableColumn('Size', 1, index: 1),
                    ],
                    rows: rows.toList(),
                    buildRow: (row) => TableRowWidget([
                      Text(row.id),
                      Text('${row.size} B'),
                    ]),
                    rowsPerPageText: 'Rows per page',
                    onRowOpen: onRowOpen,
                    // Held by the caller, as the explorer holds it: the row
                    // object that was tapped, which a new version replaces.
                    selectedRow: selected,
                    onRowTap: (row) => setState(() => selected = row),
                    onChangeMultiSelecting: (_) {},
                    sortRows: (list, column, order) {
                      final sorted = list.toList()
                        ..sort((a, b) => a.id.compareTo(b.id));
                      return order == TableSort.asc
                          ? sorted
                          : sorted.reversed.toList();
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The list pages' rule: a row at rest is flat on the table, and only
    /// a hovered or selected row is filled. Every row used to be a filled
    /// card, so the explorer always looked highlighted.
    testWidgets(
        'leaves rows at rest unfilled, and fills the selected one'
        ' in its selected colour', (tester) async {
      await pumpTable(tester, const [
        _Row(0, id: 'a', size: 640),
        _Row(1, id: 'b', size: 10),
      ]);

      Color rowColour(String id) => rowFill(tester, id);
      final table =
          ArDriveTheme.of(tester.element(find.text('a'))).themeData.tableTheme;

      expect(rowColour('a'), Colors.transparent);
      expect(rowColour('b'), Colors.transparent);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();

      expect(rowColour('a'), table.selectedItemColor);
      expect(rowColour('b'), Colors.transparent);
    });

    testWidgets('fills a hovered row, selected or not',
        (tester) async {
      await pumpTable(tester, const [
        _Row(0, id: 'a', size: 640),
        _Row(1, id: 'b', size: 10),
      ]);

      Color rowColour(String id) => rowFill(tester, id);
      final table =
          ArDriveTheme.of(tester.element(find.text('a'))).themeData.tableTheme;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('b')));
      await tester.pumpAndSettle();

      expect(rowColour('b'), table.hoverItemColor);
      expect(rowColour('a'), Colors.transparent);

      await tester.tap(find.text('b'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle(kDoubleTapTimeout);

      expect(rowColour('b'), table.selectedItemColor,
          reason: 'a selected row keeps its colour under the pointer');

      await mouse.moveTo(tester.getCenter(find.text('a')));
      await tester.pumpAndSettle();

      expect(rowColour('a'), table.hoverItemColor);
      expect(rowColour('b'), table.selectedItemColor);
    });

    test('a hovered or selected row stands out from the table in both themes',
        () {
      for (final theme in [
        ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode()),
        lightTheme(),
      ]) {
        final ground = theme.tableTheme.backgroundColor;
        expect(theme.tableTheme.selectedItemColor, isNot(ground),
            reason: theme.name);
        final hover = theme.tableTheme.hoverItemColor;
        expect(hover, isNot(ground), reason: theme.name);
        expect(hover, isNot(theme.tableTheme.selectedItemColor),
            reason: theme.name);
      }
    });

    /// The list pages' geometry: rows meet with no gap between them, are
    /// the list pages' height, and their fill reaches the table's edges.
    testWidgets('rows are flat, as tall as the list pages\', edge to edge',
        (tester) async {
      await pumpTable(tester, const [
        _Row(0, id: 'a', size: 640),
        _Row(1, id: 'b', size: 10),
      ]);
      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();

      Rect rowRect(String id) => tester.getRect(find
          .ancestor(
            of: find.text(id),
            matching: find.byWidgetPredicate(
              (w) => w is Container && w.key is ValueKey<Object>,
            ),
          )
          .first);
      final table = tester.getRect(find.byType(ArDriveDataTable<_Row>));

      expect(rowRect('a').height, ArDriveDataTable.rowHeight);
      expect(rowRect('b').top, rowRect('a').bottom, reason: 'no gap');
      expect(rowRect('a').left, table.left);
      expect(rowRect('a').right, table.right);
    });

    testWidgets('draws a row that changed while the number of rows did not',
        (tester) async {
      await pumpTable(tester, const [
        _Row(0, id: 'a', size: 640),
        _Row(1, id: 'b', size: 10),
      ]);

      expect(find.text('640 B'), findsOneWidget);

      setRows(() => rows = const [
            _Row(0, id: 'a', size: 918),
            _Row(1, id: 'b', size: 10),
          ]);
      await tester.pumpAndSettle();

      expect(find.text('918 B'), findsOneWidget);
      expect(find.text('640 B'), findsNothing);
    });

    testWidgets('opens the new copy of the selected row on Enter',
        (tester) async {
      final opened = <_Row>[];
      await pumpTable(
        tester,
        const [
          _Row(0, id: 'a', size: 640),
          _Row(1, id: 'b', size: 10),
        ],
        onRowOpen: opened.add,
      );

      await tester.tap(find.text('a'), kind: PointerDeviceKind.mouse);
      // Past the double-click window, so the next key is not a second click.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      setRows(() => rows = const [
            _Row(0, id: 'a', size: 918),
            _Row(1, id: 'b', size: 10),
          ]);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(opened.map((row) => row.size), [918]);
    });
  });
}
