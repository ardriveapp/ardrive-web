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

    testWidgets(
        'paints rows in the table\'s cell colour, and the selected one'
        ' in its selected colour', (tester) async {
      await pumpTable(tester, const [
        _Row(0, id: 'a', size: 640),
        _Row(1, id: 'b', size: 10),
      ]);

      Color rowColour(String id) => tester
          .widget<ArDriveCard>(find
              .ancestor(of: find.text(id), matching: find.byType(ArDriveCard))
              .first)
          .backgroundColor!;
      final table =
          ArDriveTheme.of(tester.element(find.text('a'))).themeData.tableTheme;

      expect(rowColour('a'), table.cellColor);
      expect(rowColour('b'), table.cellColor);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();

      expect(rowColour('a'), table.selectedItemColor);
      expect(rowColour('b'), table.cellColor);
    });

    testWidgets('shows hover on the row\'s card, selected or not',
        (tester) async {
      await pumpTable(tester, const [
        _Row(0, id: 'a', size: 640),
        _Row(1, id: 'b', size: 10),
      ]);

      Color rowColour(String id) => tester
          .widget<ArDriveCard>(find
              .ancestor(of: find.text(id), matching: find.byType(ArDriveCard))
              .first)
          .backgroundColor!;
      final table =
          ArDriveTheme.of(tester.element(find.text('a'))).themeData.tableTheme;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('b')));
      await tester.pumpAndSettle();

      expect(rowColour('b'), table.hoverItemColor);
      expect(rowColour('a'), table.cellColor);

      await tester.tap(find.text('b'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle(kDoubleTapTimeout);

      expect(rowColour('b'), table.selectedItemColor,
          reason: 'a selected row keeps its colour under the pointer');

      await mouse.moveTo(tester.getCenter(find.text('a')));
      await tester.pumpAndSettle();

      expect(rowColour('a'), table.hoverItemColor);
      expect(rowColour('b'), table.selectedItemColor);
    });

    test('a selected row looks different from the others in both themes', () {
      for (final theme in [
        ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode()),
        lightTheme(),
      ]) {
        expect(theme.tableTheme.selectedItemColor,
            isNot(theme.tableTheme.cellColor),
            reason: theme.name);
        final hover = theme.tableTheme.hoverItemColor;
        expect(hover, isNot(theme.tableTheme.cellColor), reason: theme.name);
        expect(hover, isNot(theme.tableTheme.selectedItemColor),
            reason: theme.name);
      }
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
