import 'package:ardrive/components/list_page/list_table.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:flutter_test/flutter_test.dart';

class _Row extends IndexedItem {
  const _Row(super.index, this.name);

  final String name;

  @override
  List<Object?> get props => [index, name];
}

/// The explorer's table and the drives list agree on four small things: a row
/// stays marked while its menu is open, the checkbox sits 14 from the content,
/// the whole checkbox column ticks, and a dialog keeps its keys.
void main() {
  const rows = [_Row(0, 'Holidays'), _Row(1, 'Receipts')];
  final theme = lightTheme();
  late List<String> tapped;

  setUp(() => tapped = []);

  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    return gesture;
  }

  const menuItems = [ArDriveDropdownItem(content: Text('Rename'))];

  Future<void> pumpExplorer(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: theme,
        child: MaterialApp(
          home: Portal(
            child: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const AlertDialog(
                          content: TextField(autofocus: true),
                        ),
                      ),
                      child: const Text('Dialog'),
                    ),
                    Expanded(
                      child: ArDriveDataTable<_Row>(
                        columns: [TableColumn('Name', 1, index: 0)],
                        rows: rows,
                        rowsPerPageText: 'Rows per page',
                        buildRow: (row) => TableRowWidget([Text(row.name)]),
                        onRowTap: (row) => tapped.add(row.name),
                        onChangeMultiSelecting: (_) {},
                        trailing: (row) => ArDriveDropdown(
                          items: menuItems,
                          child: Icon(Icons.more_vert,
                              key: Key('kebab-${row.name}')),
                        ),
                        trailingWidth: (_) => 48,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Color? explorerRowColour(WidgetTester tester, _Row row) => tester
      .widget<Container>(find.byWidgetPredicate(
        (w) => w is Container && w.key == ValueKey(row),
      ))
      .color;

  Iterable<bool> ticks(WidgetTester tester) =>
      tester.widgetList<ArDriveCheckBox>(find.byType(ArDriveCheckBox)).map(
            (box) => box.checked,
          );

  testWidgets('a menu removed while open tells its row it closed',
      (tester) async {
    final heard = <bool>[];
    var showMenu = true;
    late StateSetter setOuter;
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: theme,
        child: MaterialApp(
          home: Portal(
            child: Scaffold(
              body: StatefulBuilder(builder: (context, setState) {
                setOuter = setState;
                return ArDriveRowMenuScope(
                  onOpenChanged: heard.add,
                  child: showMenu
                      ? const ArDriveDropdown(
                          items: menuItems,
                          child: Icon(Icons.more_vert, key: Key('k')),
                        )
                      : const SizedBox(),
                );
              }),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('k')));
    await tester.pumpAndSettle();
    expect(heard, [true]);

    // As when Delete in the menu removes the row's own item.
    setOuter(() => showMenu = false);
    await tester.pumpAndSettle();

    expect(heard, [true, false]);
  });

  group('explorer table', () {
    testWidgets('a row is marked while its menu is open, and not after',
        (tester) async {
      await pumpExplorer(tester);
      final table = theme.tableTheme;
      expect(explorerRowColour(tester, rows[0]), Colors.transparent);

      await tester.tap(find.byKey(const Key('kebab-Holidays')));
      await tester.pumpAndSettle();

      expect(find.text('Rename'), findsOneWidget);
      expect(explorerRowColour(tester, rows[0]), table.hoverItemColor);
      expect(explorerRowColour(tester, rows[1]), Colors.transparent);
      expect(tapped, isEmpty, reason: 'a menu does not choose its row');

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.text('Rename'), findsNothing);
      expect(explorerRowColour(tester, rows[0]), Colors.transparent);
    });

    testWidgets('the checkbox sits 14 from the content and the header agrees',
        (tester) async {
      await pumpExplorer(tester);

      final box = find.byType(ArDriveCheckBox).at(1);
      final gap = tester.getTopLeft(find.text('Holidays')).dx -
          tester.getTopLeft(box).dx -
          18.5;
      expect(gap, inInclusiveRange(12, 16));
      expect(
        tester.getTopLeft(find.text('Name')).dx -
            tester.getTopLeft(find.text('Holidays')).dx,
        lessThanOrEqualTo(5),
        reason: 'the heading stays over the names',
      );
    });

    testWidgets('a tap beside the glyph ticks the box and nothing else',
        (tester) async {
      await pumpExplorer(tester);
      final pointer = await mouse(tester);
      final box = find.byType(ArDriveCheckBox).at(1);
      final glyph = tester.getRect(box);
      await pointer.moveTo(tester.getCenter(find.text('Holidays')));
      await tester.pump(const Duration(milliseconds: 200));

      // Right of the glyph and a few pixels below it, still in the column.
      await pointer.down(Offset(glyph.right + 8, glyph.center.dy + 12));
      await pointer.up();
      await tester.pump();

      expect(ticks(tester).where((t) => t), hasLength(1));
      expect(tapped, isEmpty);
    });

    testWidgets('select all in a dialog text field leaves the table alone',
        (tester) async {
      await pumpExplorer(tester);
      await tester.tap(find.text('Dialog'));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(ticks(tester).where((t) => t), isEmpty);
    });

    testWidgets('Esc in a dialog does not clear the selection behind it',
        (tester) async {
      await pumpExplorer(tester);
      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(find.text('Holidays')));
      await tester.pump(const Duration(milliseconds: 200));
      await pointer.down(tester.getCenter(find.byType(ArDriveCheckBox).at(1)));
      await pointer.up();
      await tester.pump();
      expect(ticks(tester).where((t) => t), hasLength(1));

      await tester.tap(find.text('Dialog'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(ticks(tester).where((t) => t), hasLength(1));
    });
  });

  group('drives list', () {
    var ticked = <String>[];

    Future<void> pumpList(WidgetTester tester) async {
      ticked = [];
      await tester.binding.setSurfaceSize(const Size(1000, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ArDriveTheme(
          themeData: theme,
          child: MaterialApp(
            home: Portal(
              child: Scaffold(
                body: Column(
                  children: [
                    ListTableRow(
                      semanticLabel: 'one',
                      showsColumns: true,
                      onOpen: () => tapped.add('open'),
                      onChoose: () => tapped.add('choose'),
                      chosen: false,
                      selection: ListRowSelection(
                        ticked: false,
                        onTickChanged: () => ticked.add('one'),
                        selecting: false,
                      ),
                      menu: const ListRowMenu(items: menuItems, label: 'Menu'),
                      child: const Text('one name'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    Color? listRowColour(WidgetTester tester) => tester
        .widget<ColoredBox>(
          find
              .descendant(
                of: find.byType(ListRowHighlight),
                matching: find.byType(ColoredBox),
              )
              .first,
        )
        .color;

    testWidgets('a row is marked while its menu is open, and not after',
        (tester) async {
      await pumpList(tester);
      expect(listRowColour(tester), Colors.transparent);

      await tester.tap(find.byType(ListRowMenu));
      await tester.pumpAndSettle();

      expect(find.text('Rename'), findsOneWidget);
      expect(listRowColour(tester), theme.tableTheme.hoverItemColor);

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(listRowColour(tester), isNot(theme.tableTheme.hoverItemColor));
    });

    testWidgets('the checkbox sits 14 from the content', (tester) async {
      await pumpList(tester);

      final gap = tester.getTopLeft(find.text('one name')).dx -
          tester.getTopLeft(find.byType(ArDriveCheckBox)).dx -
          18.5;
      expect(gap, inInclusiveRange(12, 16));
    });

    testWidgets('a tap beside the glyph ticks the box and does not open',
        (tester) async {
      await pumpList(tester);
      final pointer = await mouse(tester);
      final glyph = tester.getRect(find.byType(ArDriveCheckBox));
      await pointer.moveTo(tester.getCenter(find.text('one name')));
      await tester.pump(const Duration(milliseconds: 200));

      await pointer.down(Offset(glyph.right + 8, glyph.center.dy + 12));
      await pointer.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

      expect(ticked, ['one']);
      expect(tapped, isEmpty);
    });
  });
}
