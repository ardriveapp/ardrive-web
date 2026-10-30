import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The row every context menu is built from.
void main() {
  Widget wrap(Widget child, {ArDriveThemeData? theme}) => ArDriveTheme(
        themeData: theme ?? lightTheme(),
        child: MaterialApp(home: Scaffold(body: child)),
      );

  Color labelColour(WidgetTester tester, String name) =>
      tester.widget<Text>(find.text(name)).style!.color!;

  for (final (name, theme) in [
    ('light', lightTheme()),
    ('dark', ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode())),
  ]) {
    testWidgets('draws its label in the $name theme\'s text colours',
        (tester) async {
      await tester.pumpWidget(wrap(
        const ArDriveDropdownItemTile(name: 'Rename'),
        theme: theme,
      ));
      expect(labelColour(tester, 'Rename'), theme.colorTokens.textHigh);

      await tester.pumpWidget(wrap(
        const ArDriveDropdownItemTile(name: 'Rename', isDisabled: true),
        theme: theme,
      ));
      expect(labelColour(tester, 'Rename'), theme.colorTokens.textXLow);
    });
  }

  testWidgets('an icon takes the label colour unless it has its own',
      (tester) async {
    final tokens = lightTheme().colorTokens;
    const red = Color(0xffd31721);

    await tester.pumpWidget(wrap(Column(children: [
      ArDriveDropdownItemTile(name: 'Share', icon: ArDriveIcons.share()),
      ArDriveDropdownItemTile(
        name: 'Delete',
        icon: ArDriveIcons.closeCircle(color: red),
      ),
      ArDriveDropdownItemTile(
        name: 'Hide',
        icon: ArDriveIcons.closeCircle(color: red),
        isDisabled: true,
      ),
    ])));

    final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
    expect(icons[0].color, tokens.textHigh);
    expect(icons[1].color, red, reason: 'a red delete stays red');
    expect(icons[2].color, tokens.textXLow, reason: 'disabled greys it');
  });
}
