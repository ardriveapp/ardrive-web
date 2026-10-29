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

  testWidgets(
      'a dialog opened from an open card takes its own clicks, and the card '
      'comes back when it closes', (tester) async {
    late BuildContext pageContext;
    var visible = true;

    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            pageContext = context;
            return StatefulBuilder(
              builder: (context, setState) => ArDriveOverlay(
                visible: visible,
                onVisibleChange: (value) => setState(() => visible = value),
                anchor: const Aligned(
                  follower: Alignment.topLeft,
                  target: Alignment.bottomLeft,
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The card's Wallet section, opened before the dialog.
                    const ExpansionTile(
                      title: Text('Wallet'),
                      children: [Text('ArNS wallet')],
                    ),
                    TextButton(
                      // The keyfile download in the profile card: a dialog
                      // over the page while the card stays open.
                      onPressed: () => showDialog<void>(
                        context: pageContext,
                        builder: (context) => Center(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ),
                      child: const Text('Download wallet backup'),
                    ),
                  ],
                ),
                child: const SizedBox(width: 40, height: 40),
              ),
            );
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
    expect(find.text('ArNS wallet'), findsOneWidget);

    await tester.tap(find.text('Download wallet backup'));
    await tester.pumpAndSettle();
    // The card steps aside, so nothing of it lies over the dialog.
    expect(find.text('Download wallet backup').hitTestable(), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsNothing, reason: 'the dialog closed');
    expect(visible, isTrue, reason: 'the click was not the card\'s barrier');
    expect(find.text('Download wallet backup'), findsOneWidget);
    expect(find.text('ArNS wallet'), findsOneWidget,
        reason: 'the card comes back as it was');
  });

  testWidgets('a tap in a dialog over an open ArDriveSubmenu leaves it open',
      (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(page(Builder(builder: (context) {
      pageContext = context;
      return ArDriveSubmenu(
        menuChildren: [
          ArDriveSubmenuItem(widget: const Text('New drive'), onClick: () {}),
        ],
        child: const SizedBox(width: 40, height: 40, child: Text('New')),
      );
    })));
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();

    // Something else opens a dialog while the menu is open.
    showDialog<void>(
      context: pageContext,
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('New drive'), findsOneWidget);
  });
}
