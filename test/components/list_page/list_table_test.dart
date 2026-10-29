import 'package:ardrive/components/list_page/list_table.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The table every list page draws: Your drives, Web pages, Names and one
/// name's records.
void main() {
  late List<String> sorted;
  late List<String> opened;
  late List<String> chosen;

  setUp(() {
    sorted = [];
    opened = [];
    chosen = [];
  });

  const columns = [
    ListColumn<String>('Page', 6, sortKey: 'name'),
    ListColumn<String>('Link', 5),
    ListColumn<String>('Updated', 3, sortKey: 'updated'),
  ];

  Future<void> pump(
    WidgetTester tester, {
    bool showsColumns = true,
    bool? selected,
    bool showsCheckbox = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ListTableHeader<String>(
                  columns: columns,
                  sort: 'updated',
                  sortAscending: false,
                  onSort: sorted.add,
                  allSelected: selected,
                  showsCheckbox: showsCheckbox,
                ),
                for (final row in ['one', 'two'])
                  ListTableRow(
                    semanticLabel: row,
                    showsColumns: showsColumns,
                    onOpen: () => opened.add(row),
                    onChoose: () => chosen.add(row),
                    chosen: false,
                    selected: selected,
                    showsCheckbox: showsCheckbox,
                    menu: const SizedBox(width: 48, height: 48),
                    child: ListColumnsRow(
                      flexes: const [6, 5, 3],
                      cells: [
                        ListNameCell(
                          icon: const Icon(Icons.web, size: 20),
                          title: row,
                          subtitle: '$row source',
                        ),
                        ListTextCell('$row.ar.io'),
                        ListTextCell('$row date'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    return gesture;
  }

  Future<void> click(
      WidgetTester tester, TestGesture pointer, String text) async {
    await pointer.down(tester.getCenter(find.text(text)));
    await pointer.up();
    await tester.pump();
  }

  testWidgets('each heading sits over its own column', (tester) async {
    await pump(tester);

    expect(
      tester.getTopLeft(find.text('Link')).dx,
      tester.getTopLeft(find.text('one.ar.io')).dx,
    );
    expect(
      tester.getTopLeft(find.text('Updated')).dx,
      tester.getTopLeft(find.text('one date')).dx,
    );
  });

  testWidgets('a sortable heading sorts; a plain one does not', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Page'));
    await tester.tap(find.text('Link'));
    await tester.pump();

    expect(sorted, ['name']);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget,
        reason: 'the sorting column says which way');
  });

  testWidgets('a click chooses the row; it does not open it', (tester) async {
    await pump(tester);
    final pointer = await mouse(tester);

    await click(tester, pointer, 'two');
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

    expect(chosen, contains('two'));
    expect(opened, isEmpty);
  });

  testWidgets('a double-click opens it', (tester) async {
    await pump(tester);
    final pointer = await mouse(tester);

    await click(tester, pointer, 'two');
    await tester.pump(const Duration(milliseconds: 100));
    await click(tester, pointer, 'two');

    expect(opened, ['two']);
  });

  testWidgets('a tap on a touch screen opens it', (tester) async {
    await pump(tester);

    await tester.tap(find.text('one'), kind: PointerDeviceKind.touch);
    await tester.pump();

    expect(opened, ['one']);
  });

  testWidgets('a row is as tall as a drives list row', (tester) async {
    await pump(tester);

    // Content inside the row's padding either side, never shorter than its
    // menu's tap target.
    expect(
      tester.getSize(find.byType(ListTableRow).first).height,
      greaterThanOrEqualTo(listMenuTapTarget),
    );
  });

  group('a list that hides its checkboxes until the reader chooses several',
      () {
    testWidgets('draws none, and the headings stay over their columns',
        (tester) async {
      await pump(tester, selected: false, showsCheckbox: false);
      await tester.pumpAndSettle();

      expect(find.byType(ArDriveCheckBox), findsNothing);
      expect(
        tester.getTopLeft(find.text('Link')).dx,
        tester.getTopLeft(find.text('one.ar.io')).dx,
      );
    });

    testWidgets('and lines up with a list that offers no selection at all',
        (tester) async {
      await pump(tester);
      final plain = tester.getTopLeft(find.text('one')).dx;

      await pump(tester, selected: false, showsCheckbox: false);
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('one')).dx, plain);
    });

    testWidgets('shown, one per row and select-all, still in line',
        (tester) async {
      await pump(tester, selected: false);
      await tester.pumpAndSettle();

      expect(find.byType(ArDriveCheckBox), findsNWidgets(3));
      expect(
        tester.getTopLeft(find.text('Link')).dx,
        tester.getTopLeft(find.text('one.ar.io')).dx,
      );
    });
  });
}
