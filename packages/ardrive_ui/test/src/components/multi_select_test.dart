import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// When a list shows its checkboxes: the file-manager pattern, shared by the
/// explorer's table and the drives list.
void main() {
  group('ArDriveMultiSelect', () {
    test(
        'selecting: once something is ticked, while the key is held, or '
        'after a long press', () {
      expect(
        ArDriveMultiSelect.isSelecting(anyTicked: false, keyHeld: false),
        isFalse,
      );
      expect(
        ArDriveMultiSelect.isSelecting(anyTicked: true, keyHeld: false),
        isTrue,
      );
      expect(
        ArDriveMultiSelect.isSelecting(anyTicked: false, keyHeld: true),
        isTrue,
      );
      expect(
        ArDriveMultiSelect.isSelecting(
          anyTicked: false,
          keyHeld: false,
          longPressed: true,
        ),
        isTrue,
      );
    });

    test("a row's box: while selecting, hovered or focused", () {
      expect(ArDriveMultiSelect.showsRowCheckbox(selecting: false), isFalse);
      expect(ArDriveMultiSelect.showsRowCheckbox(selecting: true), isTrue);
      expect(
        ArDriveMultiSelect.showsRowCheckbox(selecting: false, hovered: true),
        isTrue,
      );
      expect(
        ArDriveMultiSelect.showsRowCheckbox(selecting: false, focused: true),
        isTrue,
      );
    });
  });

  group('ArDriveMultiSelectBox', () {
    Future<void> pump(WidgetTester tester, {required bool visible}) =>
        tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ArDriveMultiSelectBox(
                visible: visible,
                width: 40,
                child: const SizedBox(key: Key('box'), width: 18, height: 18),
              ),
              const Text('name', key: Key('name')),
            ],
          ),
        ));

    testWidgets('keeps its width hidden or shown, so nothing beside it moves',
        (tester) async {
      await pump(tester, visible: false);
      await tester.pumpAndSettle();
      final hidden = tester.getTopLeft(find.byKey(const Key('name')));

      await pump(tester, visible: true);
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byKey(const Key('name'))), hidden);
      expect(tester.getSize(find.byType(ArDriveMultiSelectBox)).width, 40);
    });

    testWidgets('hidden, it is transparent and takes no pointer',
        (tester) async {
      await pump(tester, visible: false);
      await tester.pumpAndSettle();

      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );
      expect(
        tester
            .widget<IgnorePointer>(find
                .ancestor(
                  of: find.byKey(const Key('box')),
                  matching: find.byType(IgnorePointer),
                )
                .first)
            .ignoring,
        isTrue,
      );
    });
  });

  testWidgets('ArDriveMultiSelectKey follows the key down and up',
      (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(ArDriveMultiSelectKey(
      builder: (context, held) {
        seen.add(held);
        return const SizedBox();
      },
    ));

    // Cmd: the test platform is not Windows.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(seen, [false, true, false]);
  });

  testWidgets('and is not moved by other keys', (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(ArDriveMultiSelectKey(
      builder: (context, held) {
        seen.add(held);
        return const SizedBox();
      },
    ));

    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(seen, [false]);
  });

  group("the explorer's table", () {
    Future<void> pumpTable(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: ArDriveDataTable<_Row>(
              columns: [TableColumn('Name', 1, index: 0)],
              rows: const [_Row(0, 'one'), _Row(1, 'two')],
              buildRow: (row) => TableRowWidget([Text(row.id)]),
              rowsPerPageText: 'Rows per page',
              onChangeMultiSelecting: (_) {},
              onRowOpen: (_) {},
              sortRows: (list, column, order) => list,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    List<bool> shown(WidgetTester tester) => tester
        .widgetList<ArDriveMultiSelectBox>(find.byType(ArDriveMultiSelectBox))
        .map((b) => b.visible)
        .toList();

    Future<TestGesture> mouse(WidgetTester tester) async {
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: const Offset(1, 1));
      addTearDown(g.removePointer);
      return g;
    }

    testWidgets("hover shows that row's box only", (tester) async {
      await pumpTable(tester);
      // Select-all, then one per row.
      expect(shown(tester), [false, false, false]);

      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(find.text('two')));
      await tester.pumpAndSettle();

      expect(shown(tester), [false, false, true]);
    });

    testWidgets("keyboard focus shows the chosen row's box", (tester) async {
      await pumpTable(tester);
      final pointer = await mouse(tester);

      // A click chooses the row and puts focus in the table, where Enter
      // opens it; the pointer then leaves.
      await pointer.down(tester.getCenter(find.text('one')));
      await pointer.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await pointer.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();

      expect(shown(tester), [false, true, false]);
    });

    testWidgets('a tick shows every box and select-all', (tester) async {
      await pumpTable(tester);
      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(find.text('one')));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ArDriveCheckBox).at(1));
      await tester.pumpAndSettle();
      await pointer.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();

      expect(shown(tester), [true, true, true]);
    });

    testWidgets("a row's content does not move when its box shows",
        (tester) async {
      await pumpTable(tester);
      final before = tester.getTopLeft(find.text('two'));

      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(find.text('two')));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('two')), before);
      expect(tester.getTopLeft(find.text('Name')).dx, isNonZero);
    });
  });
}

class _Row extends IndexedItem {
  const _Row(super.index, this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}
