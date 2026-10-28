import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// With the browser's accessibility tree on, the web engine stacks semantics
/// nodes in tree order, and a mouse click goes to the node on top. A menu's
/// items have to come after the page they cover, or a click on an item lands
/// on the row behind it. They did not: the menus' nodes sat where their
/// buttons are, before every row after the button (#2347).
void main() {
  /// Every node, in the order the web engine stacks them.
  List<SemanticsNode> inTreeOrder(WidgetTester tester) {
    final nodes = <SemanticsNode>[];
    void visit(SemanticsNode node) {
      nodes.add(node);
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(tester.getSemantics(find.byType(Scaffold)).owner!.rootSemanticsNode!);
    return nodes;
  }

  int indexOfLabel(List<SemanticsNode> nodes, String label) =>
      nodes.indexWhere((node) => node.label == label);

  /// A menu's button, then a row after it that the open menu covers.
  Widget page(Widget menu) => ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                menu,
                Semantics(
                  button: true,
                  label: 'The row underneath',
                  child: const SizedBox(width: 400, height: 200),
                ),
              ],
            ),
          ),
        ),
      );

  testWidgets('an ArDriveDropdown\'s items lie over the page after it',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(page(
      ArDriveDropdown(
        items: [
          ArDriveDropdownItem(content: const Text('More info'), onClick: () {}),
        ],
        child: const SizedBox(width: 40, height: 40, child: Text('Menu')),
      ),
    ));
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();

    final nodes = inTreeOrder(tester);
    expect(
      indexOfLabel(nodes, 'More info'),
      greaterThan(indexOfLabel(nodes, 'The row underneath')),
    );
    handle.dispose();
  });

  testWidgets('an ArDriveSubmenu\'s items lie over the page after it',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(page(
      ArDriveSubmenu(
        menuChildren: [
          ArDriveSubmenuItem(widget: const Text('New drive'), onClick: () {}),
        ],
        child: const SizedBox(width: 40, height: 40, child: Text('New')),
      ),
    ));
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();

    final nodes = inTreeOrder(tester);
    expect(
      indexOfLabel(nodes, 'New drive'),
      greaterThan(indexOfLabel(nodes, 'The row underneath')),
    );
    handle.dispose();
  });

  testWidgets('an ArDriveSubmenu item runs its action and closes the menu',
      (tester) async {
    var created = 0;
    await tester.pumpWidget(page(
      ArDriveSubmenu(
        menuChildren: [
          ArDriveSubmenuItem(
            widget: const Text('New drive'),
            onClick: () => created++,
          ),
        ],
        child: const SizedBox(width: 40, height: 40, child: Text('New')),
      ),
    ));
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New drive'));
    await tester.pumpAndSettle();

    expect(created, 1);
    expect(find.text('New drive'), findsNothing);
  });

  testWidgets('an ArDriveSubmenu closes on Escape and on a click outside',
      (tester) async {
    await tester.pumpWidget(page(
      ArDriveSubmenu(
        menuChildren: [
          ArDriveSubmenuItem(widget: const Text('New drive'), onClick: () {}),
        ],
        child: const SizedBox(width: 40, height: 40, child: Text('New')),
      ),
    ));

    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('New drive'), findsNothing);

    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(390, 560));
    await tester.pumpAndSettle();
    expect(find.text('New drive'), findsNothing);
  });
}
