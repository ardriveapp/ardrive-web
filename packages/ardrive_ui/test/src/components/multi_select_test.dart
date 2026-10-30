import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/foundation.dart';
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

    testWidgets('hidden, it is transparent and a click passes through',
        (tester) async {
      var boxTaps = 0;
      var behindTaps = 0;
      Future<void> pumpOver({required bool visible}) =>
          tester.pumpWidget(Directionality(
            textDirection: TextDirection.ltr,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => behindTaps++,
              child: ArDriveMultiSelectBox(
                visible: visible,
                width: 40,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => boxTaps++,
                  child: const SizedBox(key: Key('box'), width: 18, height: 18),
                ),
              ),
            ),
          ));

      await pumpOver(visible: false);
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );
      await tester.tap(find.byKey(const Key('box')), warnIfMissed: false);
      expect([boxTaps, behindTaps], [0, 1]);

      await pumpOver(visible: true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('box')));
      expect([boxTaps, behindTaps], [1, 1]);
    });
  });

  group('the multi-select key', () {
    testWidgets('is Ctrl off Apple platforms', (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(ArDriveMultiSelect.keyPressed, isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      expect(ArDriveMultiSelect.keyPressed, isFalse,
          reason: 'Meta is Super on Linux and ChromeOS');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    });

    testWidgets('and Cmd on macOS and iOS', (tester) async {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        expect(ArDriveMultiSelect.keyPressed, isTrue);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        expect(ArDriveMultiSelect.keyPressed, isFalse);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('already held when the list is built counts', (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      bool? held;
      await tester.pumpWidget(ArDriveMultiSelectKey(
        builder: (context, h) {
          held = h;
          return const SizedBox();
        },
      ));
      expect(held, isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
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

    // Ctrl: the test platform is not macOS or iOS.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
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
    late List<List<int>> selections;

    Future<void> pumpTable(
      WidgetTester tester, {
      bool locked = false,
      void Function(_Row row)? onRowOpen,
    }) async {
      selections = [];
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: ArDriveDataTable<_Row>(
              columns: [TableColumn('Name', 1, index: 0)],
              rows: const [_Row(0, 'one'), _Row(1, 'two')],
              // In a tooltip, as the explorer's names are.
              buildRow: (row) => TableRowWidget([
                ArDriveTooltip(message: row.id, child: Text(row.id)),
              ]),
              rowsPerPageText: 'Rows per page',
              onChangeMultiSelecting: (_) {},
              onRowOpen: onRowOpen ?? (_) {},
              lockMultiSelect: locked,
              onSelectedRows: (boxes) => selections.add([
                for (final box in boxes)
                  for (final row in box.selectedItems) row.index,
              ]),
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
      await pointer.moveTo(tester.getCenter(find.text('two').first));
      await tester.pumpAndSettle();

      expect(shown(tester), [false, false, true]);
    });

    testWidgets("keyboard focus shows the chosen row's box", (tester) async {
      await pumpTable(tester);
      final pointer = await mouse(tester);

      // A click chooses the row and puts focus in the table, where Enter
      // opens it; the pointer then leaves.
      await pointer.down(tester.getCenter(find.text('one').first));
      await pointer.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await pointer.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();

      expect(shown(tester), [false, true, false]);
    });

    Future<void> chooseRow(
      WidgetTester tester,
      String name, [
      TestGesture? existing,
    ]) async {
      final pointer = existing ?? await mouse(tester);
      await pointer.down(tester.getCenter(find.text(name).first));
      await pointer.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await pointer.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
    }

    testWidgets(
        "Space ticks the chosen row's box, twice unticks, and the "
        'table keeps focus', (tester) async {
      await pumpTable(tester);
      await chooseRow(tester, 'two');
      final focused = FocusManager.instance.primaryFocus;

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(selections.last, [1]);
      expect(shown(tester), [true, true, true]);
      expect(FocusManager.instance.primaryFocus, same(focused));

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(selections.last, isEmpty);
      expect(FocusManager.instance.primaryFocus, same(focused));
    });

    testWidgets('no box shows while multi-select is locked', (tester) async {
      // A sync reading the drive locks it: a box that ticks and selects
      // nothing is worse than none.
      await pumpTable(tester, locked: true);
      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(find.text('two').first));
      await tester.pumpAndSettle();
      expect(shown(tester), [false, false, false]);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(shown(tester), [false, false, false]);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      await chooseRow(tester, 'two', pointer);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(selections, isEmpty, reason: 'Space selects nothing either');
    });

    testWidgets(
        'a long press while locked starts nothing, and taps still '
        'choose rows', (tester) async {
      final opened = <String>[];
      await pumpTable(tester,
          locked: true, onRowOpen: (row) => opened.add(row.id));

      await tester.longPress(find.text('one').first);
      await tester.pumpAndSettle();
      expect(shown(tester), [false, false, false]);
      opened.clear();

      // On touch a tap opens; after the long press it went to a refused tick
      // instead, and nothing happened.
      await tester.tap(find.text('two').first);
      await tester.pumpAndSettle();
      expect(opened, ['two']);
    });

    testWidgets('the row boxes are not Tab stops', (tester) async {
      await pumpTable(tester);
      final labels = <String?>[];
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        labels.add(FocusManager.instance.primaryFocus?.debugLabel);
      }
      expect(labels, isNot(contains('ArDriveCheckBox')));
    });

    testWidgets('holding the multi-select key shows every box', (tester) async {
      await pumpTable(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(shown(tester), [true, true, true]);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(shown(tester), [false, false, false]);
    });

    testWidgets('a long press on a cell with a tooltip starts selecting',
        (tester) async {
      await pumpTable(tester);

      await tester.longPress(find.text('one').first);
      await tester.pumpAndSettle();

      expect(shown(tester), [true, true, true]);
    });

    testWidgets('a tick shows every box and select-all', (tester) async {
      await pumpTable(tester);
      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(find.text('one').first));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ArDriveCheckBox).at(1));
      await tester.pumpAndSettle();
      await pointer.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();

      expect(shown(tester), [true, true, true]);
    });

    testWidgets('the headings and cells stay put as the boxes show',
        (tester) async {
      await pumpTable(tester);
      double heading() => tester.getTopLeft(find.text('Name')).dx;
      double cell() => tester.getTopLeft(find.text('one').first).dx;
      final hidden = [heading(), cell()];

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect([heading(), cell()], hidden, reason: 'nothing moves');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets("a row's content does not move when its box shows",
        (tester) async {
      await pumpTable(tester);
      final before = tester.getTopLeft(find.text('two').first);

      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(find.text('two').first));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('two').first), before);
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
