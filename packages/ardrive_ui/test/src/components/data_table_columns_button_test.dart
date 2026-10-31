import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Row extends IndexedItem {
  const _Row(super.index, {required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}

/// The column chooser was a bare plus with no name, which read as "add an
/// item" (#82). It is a columns glyph named for what it does.
void main() {
  Future<void> pump(WidgetTester tester, {String? columnsText}) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: columnsText == null
                ? ArDriveDataTable<_Row>(
                    columns: [TableColumn('Name', 1, index: 0)],
                    rows: const [_Row(0, id: 'a')],
                    buildRow: (row) => TableRowWidget([Text(row.id)]),
                    rowsPerPageText: 'Rows per page',
                    onChangeMultiSelecting: (_) {},
                    sortRows: (list, column, order) => list,
                  )
                : ArDriveDataTable<_Row>(
                    columns: [TableColumn('Name', 1, index: 0)],
                    rows: const [_Row(0, id: 'a')],
                    buildRow: (row) => TableRowWidget([Text(row.id)]),
                    rowsPerPageText: 'Rows per page',
                    columnsText: columnsText,
                    onChangeMultiSelecting: (_) {},
                    sortRows: (list, column, order) => list,
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('is a columns icon, not a plus', (tester) async {
    await pump(tester);

    expect(find.byIcon(Icons.view_column_outlined), findsOneWidget);
    expect(find.byIcon(ArDriveIcons.plus().icon), findsNothing);
  });

  testWidgets('is named Columns for a tooltip and a screen reader',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    expect(
      find.byWidgetPredicate(
        (w) => w is ArDriveTooltip && w.message == 'Columns',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Columns'), findsOneWidget);
    // The named node is the one a screen reader activates.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Columns')),
      matchesSemantics(
        label: 'Columns',
        isButton: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('takes its name from the app, for other languages',
      (tester) async {
    await pump(tester, columnsText: 'Columnas');

    expect(
      find.byWidgetPredicate(
        (w) => w is ArDriveTooltip && w.message == 'Columnas',
      ),
      findsOneWidget,
    );
  });

  // B4: view options, such as Show hidden items, sit under the columns.
  testWidgets('lists view options under the columns, and reports a tick',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final changes = <bool>[];

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: ArDriveDataTable<_Row>(
              columns: [TableColumn('Name', 1, index: 0)],
              rows: const [_Row(0, id: 'a')],
              buildRow: (row) => TableRowWidget([Text(row.id)]),
              rowsPerPageText: 'Rows per page',
              viewOptions: [
                ViewOption(
                  label: 'Show hidden items',
                  checked: false,
                  onChanged: changes.add,
                ),
              ],
              onChangeMultiSelecting: (_) {},
              sortRows: (list, column, order) => list,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.view_column_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Show hidden items'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Show hidden items')).dy,
      greaterThan(tester.getTopLeft(find.text('Name').last).dy),
    );

    await tester.tap(find.text('Show hidden items'));
    await tester.pumpAndSettle();

    expect(changes, [true]);
  });
}
