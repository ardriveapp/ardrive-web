import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('the chosen button is filled, in ${dark ? 'dark' : 'light'}',
        (tester) async {
      final handle = tester.ensureSemantics();
      String? picked;
      await tester.pumpWidget(ArDriveApp(
        themeData: ArDriveThemeData(
          colorTokens: dark
              ? ArDriveColorTokens.darkMode()
              : ArDriveColorTokens.lightMode(),
        ),
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: ArDriveIconSegmentedControl<String>(
                selected: 'a',
                onSelected: (v) => picked = v,
                segments: const [
                  ArDriveIconSegment(
                      value: 'a', icon: Icons.view_list, label: 'List'),
                  ArDriveIconSegment(
                      value: 'b', icon: Icons.grid_view, label: 'Gallery'),
                ],
              ),
            ),
          ),
        ),
      ));
      final tokens = ArDriveTheme.of(tester.element(find.byType(Scaffold)))
          .themeData
          .colorTokens;
      expect(tester.widget<Icon>(find.byIcon(Icons.view_list)).color,
          tokens.containerRaised);
      expect(tester.widget<Icon>(find.byIcon(Icons.grid_view)).color,
          tokens.textHigh);
      expect(
          tester
              .getSemantics(find.bySemanticsLabel('List'))
              .hasFlag(SemanticsFlag.isSelected),
          isTrue);
      expect(
          tester
              .getSize(find.byType(ArDriveIconSegmentedControl<String>))
              .height,
          ArDriveIconSegmentedControl.height);

      await tester.tap(find.byIcon(Icons.grid_view));
      expect(picked, 'b');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(picked, 'a');
      handle.dispose();
    });
  }
}
