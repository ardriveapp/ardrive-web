import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
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

    Future<void> pumpTable(WidgetTester tester, List<_Row> initial) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      rows = initial;

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
  });
}
