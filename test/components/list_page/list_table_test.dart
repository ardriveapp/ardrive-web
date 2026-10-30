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
  late List<String> ticked;

  setUp(() {
    ticked = [];
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
    bool bulkActions = false,
    bool selecting = false,
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
                  selection: bulkActions
                      ? ListHeaderSelection(
                          allTicked: false,
                          onToggleAll: () {},
                          selecting: selecting,
                        )
                      : null,
                ),
                for (final row in ['one', 'two'])
                  ListTableRow(
                    semanticLabel: row,
                    showsColumns: showsColumns,
                    onOpen: () => opened.add(row),
                    onChoose: () => chosen.add(row),
                    chosen: false,
                    selection: bulkActions
                        ? ListRowSelection(
                            ticked: false,
                            onTickChanged: () => ticked.add(row),
                            selecting: selecting,
                          )
                        : null,
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

  group('checkboxes, the file-manager pattern', () {
    List<bool> shown(WidgetTester tester) => tester
        .widgetList<ArDriveMultiSelectBox>(find.byType(ArDriveMultiSelectBox))
        .map((b) => b.visible)
        .toList();

    testWidgets('a list without bulk actions draws none at all',
        (tester) async {
      await pump(tester);
      await tester.longPress(find.text('one'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(ArDriveCheckBox), findsNothing);
      expect(find.byType(ArDriveMultiSelectBox), findsNothing);
    });

    testWidgets("hover shows that row's box only", (tester) async {
      await pump(tester, bulkActions: true);
      await tester.pumpAndSettle();
      // Select-all, then one per row.
      expect(shown(tester), [false, false, false]);

      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(find.text('two')));
      await tester.pumpAndSettle();

      expect(shown(tester), [false, false, true]);
    });

    testWidgets("focus shows that row's box", (tester) async {
      await pump(tester, bulkActions: true);
      final pointer = await mouse(tester);

      await click(tester, pointer, 'one');
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await pointer.moveTo(Offset.zero);
      await tester.pumpAndSettle();

      expect(shown(tester), [false, true, false]);
    });

    testWidgets('only the box ticks; a click on the row does not',
        (tester) async {
      await pump(tester, bulkActions: true);
      final pointer = await mouse(tester);

      await click(tester, pointer, 'one');
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      expect(ticked, isEmpty);

      await pointer.down(tester.getCenter(find.byType(ArDriveCheckBox).at(1)));
      await pointer.up();
      await tester.pump();
      expect(ticked, ['one']);
    });

    testWidgets('while selecting, every box and select-all show',
        (tester) async {
      await pump(tester, bulkActions: true, selecting: true);
      await tester.pumpAndSettle();

      expect(shown(tester), [true, true, true]);
    });

    testWidgets('nothing moves between hidden and shown', (tester) async {
      await pump(tester, bulkActions: true);
      await tester.pumpAndSettle();
      final hidden = [
        for (final t in ['one', 'one.ar.io', 'Link'])
          tester.getTopLeft(find.text(t)),
      ];

      await pump(tester, bulkActions: true, selecting: true);
      await tester.pumpAndSettle();

      expect([
        for (final t in ['one', 'one.ar.io', 'Link'])
          tester.getTopLeft(find.text(t)),
      ], hidden);
      expect(
        tester.getTopLeft(find.text('Link')).dx,
        tester.getTopLeft(find.text('one.ar.io')).dx,
        reason: 'the headings stay over their columns',
      );
    });
  });
}
