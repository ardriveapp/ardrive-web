import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Row extends IndexedItem {
  const _Row(super.index, this.name);

  final String name;

  @override
  List<Object?> get props => [index, name];
}

/// A click selects and a double-click opens, as in Google Drive and every
/// desktop file manager.
///
/// The explorer used to open a folder on a second, separate click on a row
/// already chosen: the gesture that means rename everywhere else, and one
/// that made entering a folder slower than in any comparable app.
void main() {
  const rows = [_Row(0, 'Holidays'), _Row(1, 'Receipts')];

  late List<String> selected;
  late List<String> opened;

  setUp(() {
    selected = [];
    opened = [];
  });

  Future<void> pumpTable(
    WidgetTester tester, {
    bool opens = true,
    bool withSearch = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                if (withSearch) const TextField(key: Key('search')),
                Expanded(
                  child: ArDriveDataTable<_Row>(
                    columns: [TableColumn('Name', 1, index: 0)],
                    rows: rows,
                    rowsPerPageText: 'Rows per page',
                    buildRow: (row) => TableRowWidget([Text(row.name)]),
                    onRowTap: (row) => selected.add(row.name),
                    onRowOpen: opens ? (row) => opened.add(row.name) : null,
                    // Read unconditionally by the table's key handler on
                    // Windows, which is where these tests run.
                    onChangeMultiSelecting: (_) {},
                  ),
                ),
              ],
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
    WidgetTester tester,
    TestGesture gesture,
    String name,
  ) async {
    await gesture.down(tester.getCenter(find.text(name)));
    await gesture.up();
    await tester.pump();
  }

  /// Past the platform's double-tap window: two clicks, not a double-click.
  Future<void> waitOutDoubleClick(WidgetTester tester) =>
      tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

  group('with a mouse', () {
    testWidgets('a click selects, at once, and opens nothing', (tester) async {
      await pumpTable(tester);
      final pointer = await mouse(tester);

      await click(tester, pointer, 'Holidays');

      // No wait first: selecting must not sit out the double-click window.
      expect(selected, ['Holidays']);
      expect(opened, isEmpty);

      await waitOutDoubleClick(tester);
    });

    testWidgets('a double-click opens, once', (tester) async {
      await pumpTable(tester);
      final pointer = await mouse(tester);

      await click(tester, pointer, 'Holidays');
      await tester.pump(const Duration(milliseconds: 100));
      await click(tester, pointer, 'Holidays');

      expect(opened, ['Holidays']);
      expect(
        selected,
        ['Holidays'],
        reason: 'the second click opens; it does not select again',
      );
    });

    /// The old gesture. It now means nothing more than a click.
    testWidgets('a second, slower click on a chosen row does not open it',
        (tester) async {
      await pumpTable(tester);
      final pointer = await mouse(tester);

      await click(tester, pointer, 'Holidays');
      await waitOutDoubleClick(tester);
      await click(tester, pointer, 'Holidays');
      await waitOutDoubleClick(tester);

      expect(opened, isEmpty);
    });

    testWidgets('two quick clicks on two rows select the second',
        (tester) async {
      await pumpTable(tester);
      final pointer = await mouse(tester);

      await click(tester, pointer, 'Holidays');
      await tester.pump(const Duration(milliseconds: 100));
      await click(tester, pointer, 'Receipts');

      expect(selected, ['Holidays', 'Receipts']);
      expect(opened, isEmpty);

      await waitOutDoubleClick(tester);
    });
  });

  /// A finger has no double-click, and no hover to show what is chosen.
  testWidgets('a tap on a touch screen opens', (tester) async {
    await pumpTable(tester);

    await tester.tap(find.text('Holidays'), kind: PointerDeviceKind.touch);
    await tester.pump();

    expect(opened, ['Holidays']);
  });

  group('Enter', () {
    testWidgets('opens the chosen row', (tester) async {
      await pumpTable(tester);
      final pointer = await mouse(tester);

      await click(tester, pointer, 'Receipts');
      await waitOutDoubleClick(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(opened, ['Receipts']);
    });

    testWidgets('does nothing with no row chosen', (tester) async {
      await pumpTable(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(opened, isEmpty);
    });

    /// The handler is global, so it must leave Enter to whatever is being
    /// typed in: the search box sits right above the explorer's table.
    testWidgets('belongs to a text field while one is being typed in',
        (tester) async {
      await pumpTable(tester, withSearch: true);
      final pointer = await mouse(tester);

      await click(tester, pointer, 'Receipts');
      await waitOutDoubleClick(tester);
      await tester.tap(find.byKey(const Key('search')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(opened, isEmpty);
    });
  });

  /// The move, hide and licence dialogs draw this table to pick a row and
  /// never open one. They pass no [ArDriveDataTable.onRowOpen] and keep the
  /// behaviour they had.
  group('without a way to open', () {
    testWidgets('a double-click only selects', (tester) async {
      await pumpTable(tester, opens: false);
      final pointer = await mouse(tester);

      await click(tester, pointer, 'Holidays');
      await tester.pump(const Duration(milliseconds: 100));
      await click(tester, pointer, 'Holidays');

      expect(selected, ['Holidays', 'Holidays']);
    });

    testWidgets('and a tap on a touch screen only selects', (tester) async {
      await pumpTable(tester, opens: false);

      await tester.tap(find.text('Holidays'), kind: PointerDeviceKind.touch);
      await tester.pump();

      expect(selected, ['Holidays']);
    });
  });
}
