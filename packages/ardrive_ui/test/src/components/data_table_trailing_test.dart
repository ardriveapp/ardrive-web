import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Row extends IndexedItem {
  const _Row(super.index, {required this.id, required this.trailing});

  final String id;
  final double trailing;

  @override
  List<Object?> get props => [id];
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    double Function(_Row row)? trailingWidth,
  }) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: ArDriveDataTable<_Row>(
              columns: [TableColumn('Name', 1, index: 0)],
              rows: const [
                _Row(0, id: 'a', trailing: 40),
                _Row(1, id: 'b', trailing: 70),
              ],
              buildRow: (row) => TableRowWidget([Text(row.id)]),
              rowsPerPageText: 'Rows per page',
              trailing: (row) => SizedBox(key: Key('t-${row.id}')),
              trailingWidth: trailingWidth,
              onChangeMultiSelecting: (_) {},
              sortRows: (list, column, order) => list,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double slot(WidgetTester tester, String id) => tester
      .getSize(find
          .ancestor(
              of: find.byKey(Key('t-$id')), matching: find.byType(Container))
          .first)
      .width;

  testWidgets('every row reserves the widest trailing width', (tester) async {
    await pump(tester, trailingWidth: (row) => row.trailing);

    expect(slot(tester, 'a'), 70);
    expect(slot(tester, 'b'), 70);
  });

  testWidgets('without a trailingWidth the slot is the default',
      (tester) async {
    await pump(tester);

    expect(slot(tester, 'a'), ArDriveDataTable.defaultTrailingWidth);
  });
}
