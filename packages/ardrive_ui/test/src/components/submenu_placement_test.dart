import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ArDriveSubmenu used to be Material's MenuAnchor. It moved to the
/// navigator's overlay so clicks land on its items with the accessibility
/// tree on; these hold it to the pixels MenuAnchor drew it at.
void main() {
  const items = ['Upload file(s)', 'Upload folder', 'New drive'];
  const button = Size(128, 40);

  Widget app({
    required Offset buttonAt,
    required Widget menu,
    VisualDensity density = VisualDensity.compact,
  }) =>
      ArDriveApp(
        builder: (context) => MaterialApp(
          theme: ThemeData(visualDensity: density, useMaterial3: false),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(left: buttonAt.dx, top: buttonAt.dy, child: menu),
              ],
            ),
          ),
        ),
      );

  Widget row(String text) =>
      SizedBox(width: 180, height: 48, child: Center(child: Text(text)));

  /// Opens the menu by tapping its button and returns where each item is.
  Future<List<Rect>> itemRects(WidgetTester tester, Widget built) async {
    await tester.pumpWidget(built);
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    return [for (final item in items) tester.getRect(find.text(item))];
  }

  Widget newButton() => SizedBox.fromSize(
        size: button,
        child: const Center(child: Text('New')),
      );

  Widget materialMenu(Offset offset) {
    final controller = MenuController();
    return MenuAnchor(
      controller: controller,
      alignmentOffset: offset,
      menuChildren: [for (final item in items) row(item)],
      child: GestureDetector(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: newButton(),
      ),
    );
  }

  Widget ardriveMenu(Offset offset) => ArDriveSubmenu(
        alignmentOffset: offset,
        menuChildren: [
          for (final item in items)
            ArDriveSubmenuItem(widget: row(item), onClick: () {}),
        ],
        child: newButton(),
      );

  final cases = {
    'the sidebar New button': (const Offset(56, 112), const Offset(140, -40)),
    'a button near the bottom, where it flips up': (
      const Offset(56, 520),
      const Offset(0, 0)
    ),
    'a button near the right edge, where it is pushed back': (
      const Offset(700, 100),
      const Offset(0, 0)
    ),
  };

  for (final density in [VisualDensity.compact, VisualDensity.standard]) {
    cases.forEach((name, setup) {
      final (buttonAt, offset) = setup;
      testWidgets('$name opens where MenuAnchor opened it ($density)',
          (tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final before = await itemRects(
          tester,
          app(
            buttonAt: buttonAt,
            menu: materialMenu(offset),
            density: density,
          ),
        );
        final after = await itemRects(
          tester,
          app(
            buttonAt: buttonAt,
            menu: ardriveMenu(offset),
            density: density,
          ),
        );

        expect(after, before);
      });
    });
  }

  testWidgets('a nested menu opens beside its item, where MenuAnchor put it',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // MenuAnchor's way: an item that is itself a MenuAnchor.
    final top = MenuController();
    final nested = MenuController();
    final before = await () async {
      await tester.pumpWidget(app(
        buttonAt: const Offset(56, 112),
        menu: MenuAnchor(
          controller: top,
          alignmentOffset: const Offset(140, -40),
          menuChildren: [
            row('Upload file(s)'),
            MenuAnchor(
              controller: nested,
              menuChildren: [row('Create manifest')],
              child: GestureDetector(
                onTap: () => nested.open(),
                child: row('Advanced'),
              ),
            ),
          ],
          child: GestureDetector(
            onTap: () => top.open(),
            child: newButton(),
          ),
        ),
      ));
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      return tester.getRect(find.text('Create manifest'));
    }();

    await tester.pumpWidget(app(
      buttonAt: const Offset(56, 112),
      menu: ArDriveSubmenu(
        alignmentOffset: const Offset(140, -40),
        menuChildren: [
          ArDriveSubmenuItem(widget: row('Upload file(s)'), onClick: () {}),
          ArDriveSubmenuItem(
            widget: row('Advanced'),
            children: [
              ArDriveSubmenuItem(
                widget: row('Create manifest'),
                onClick: () {},
              ),
            ],
          ),
        ],
        child: newButton(),
      ),
    ));
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('Create manifest')), before);
  });
}
