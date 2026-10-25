import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Menus and cards as a screen reader, and the browser with its accessibility
/// tree on, find them.
///
/// The click-away barrier used to be a node of its own: the size of the
/// screen, with a tap action, and after what it covers. With the tree on, the
/// browser stacks nodes in that order, so every click on an item landed on
/// the barrier and only closed the menu. And the items were not buttons, so
/// the web gave them no role and no name.
void main() {
  Widget app(Widget child) => ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      );

  SemanticsOwner owner(WidgetTester tester) =>
      tester.getSemantics(find.byType(Scaffold)).owner!;

  /// Every node, wherever it is in the tree.
  List<SemanticsNode> allNodes(WidgetTester tester) {
    final nodes = <SemanticsNode>[];
    void visit(SemanticsNode node) {
      nodes.add(node);
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(owner(tester).rootSemanticsNode!);
    return nodes;
  }

  /// Buttons with no name, which a screen reader reads as just "button".
  Iterable<SemanticsNode> emptyButtons(WidgetTester tester) =>
      allNodes(tester).where((node) {
        final data = node.getSemanticsData();
        return data.hasFlag(SemanticsFlag.isButton) && data.label.isEmpty;
      });

  /// Every node with a tap action.
  List<SemanticsNode> tappable(WidgetTester tester) => allNodes(tester)
      .where((node) => node.getSemanticsData().hasAction(SemanticsAction.tap))
      .toList();

  /// What the screen reader, or the browser, does on a click with the tree
  /// on: the node's own tap, not a hit test.
  Future<void> tapNode(WidgetTester tester, String label) async {
    final node = tester.getSemantics(find.bySemanticsLabel(label));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
  }

  Matcher coversTheScreen(WidgetTester tester) {
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    return predicate<SemanticsNode>(
      (node) =>
          node.rect.width >= screen.width && node.rect.height >= screen.height,
      'a node the size of the screen',
    );
  }

  group('ArDriveDropdown', () {
    late List<String> clicked;

    Widget dropdown() => ArDriveDropdown(
          items: [
            ArDriveDropdownItem(
              content: const Text('Rename drive'),
              onClick: () => clicked.add('rename'),
            ),
            // No callback: what a menu offers while it cannot do it.
            const ArDriveDropdownItem(content: Text('Sync this drive')),
          ],
          child: const SizedBox(width: 48, height: 48, child: Text('Menu')),
        );

    setUp(() => clicked = []);

    testWidgets('names each item as a button, and says which cannot be used',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(app(dropdown()));
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Rename drive')),
        containsSemantics(
          label: 'Rename drive',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Sync this drive')),
        containsSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );

      semantics.dispose();
    });

    testWidgets('puts nothing over its items that a click could land on',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(app(dropdown()));
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      expect(tappable(tester), isNot(contains(coversTheScreen(tester))));

      await tapNode(tester, 'Rename drive');

      expect(clicked, ['rename']);
      expect(find.text('Rename drive'), findsNothing);

      semantics.dispose();
    });

    testWidgets('still closes on a click outside it', (tester) async {
      await tester.pumpWidget(app(dropdown()));
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Rename drive'), findsOneWidget);

      await tester.tapAt(const Offset(600, 500));
      await tester.pumpAndSettle();

      expect(find.text('Rename drive'), findsNothing);
      expect(clicked, isEmpty);
    });

    testWidgets('closes on Escape', (tester) async {
      await tester.pumpWidget(app(dropdown()));
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Rename drive'), findsNothing);
      expect(clicked, isEmpty);

      // Once closed, Escape belongs to whatever else wants it again.
      expect(
        await tester.sendKeyEvent(LogicalKeyboardKey.escape),
        isFalse,
      );
    });
  });

  group('ArDriveOverlay', () {
    testWidgets('lets a link inside the card be clicked with the tree on',
        (tester) async {
      final semantics = tester.ensureSemantics();
      var visible = false;
      var opened = false;

      await tester.pumpWidget(app(StatefulBuilder(
        builder: (context, setState) => ArDriveOverlay(
          visible: visible,
          onVisibleChange: (value) => setState(() => visible = value),
          anchor: const Aligned(
            follower: Alignment.topLeft,
            target: Alignment.bottomLeft,
          ),
          content: Semantics(
            container: true,
            button: true,
            child: GestureDetector(
              onTap: () => opened = true,
              child: const Text('Your permanence'),
            ),
          ),
          child: GestureDetector(
            onTap: () => setState(() => visible = true),
            child: const Text('Profile'),
          ),
        ),
      )));
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(tappable(tester), isNot(contains(coversTheScreen(tester))));

      await tapNode(tester, 'Your permanence');
      expect(opened, isTrue);

      semantics.dispose();
    });

    testWidgets('closes on Escape, and says so', (tester) async {
      var visible = true;

      await tester.pumpWidget(app(StatefulBuilder(
        builder: (context, setState) => ArDriveOverlay(
          visible: visible,
          onVisibleChange: (value) => setState(() => visible = value),
          anchor: const Aligned(
            follower: Alignment.topLeft,
            target: Alignment.bottomLeft,
          ),
          content: const Text('Card'),
          child: const Text('Profile'),
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Card'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(visible, isFalse);
      expect(find.text('Card'), findsNothing);
    });
  });

  group('ArDriveSubmenu', () {
    testWidgets('names each item as a button, and says which cannot be used',
        (tester) async {
      final semantics = tester.ensureSemantics();
      var opened = false;

      // As the app's sidebar does it: the opener's button is a Semantics
      // around the whole menu, which the opener's tap joins.
      await tester.pumpWidget(app(Semantics(
        button: true,
        child: ArDriveSubmenu(
          menuChildren: [
            ArDriveSubmenuItem(
              widget: const Text('Open another drive'),
              onClick: () => opened = true,
            ),
            // How the app draws a rule between groups of items.
            ArDriveSubmenuItem(
              widget: const Divider(height: 8),
              isDisabled: true,
            ),
            ArDriveSubmenuItem(
              widget: const Text('New folder'),
              onClick: () {},
              isDisabled: true,
            ),
          ],
          child: const SizedBox(width: 80, height: 40, child: Text('New')),
        ),
      )));

      // One button, named New. The opener used to be wrapped in a second,
      // empty one, which a screen reader announced as just "button".
      expect(
        tester.getSemantics(find.bySemanticsLabel('New')),
        containsSemantics(isButton: true, hasTapAction: true),
      );
      expect(emptyButtons(tester), isEmpty);

      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Open another drive')),
        containsSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('New folder')),
        containsSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );

      // Nor is the rule between groups a button: it does nothing.
      expect(emptyButtons(tester), isEmpty);

      await tapNode(tester, 'Open another drive');
      expect(opened, isTrue);

      semantics.dispose();
    });
  });
}
