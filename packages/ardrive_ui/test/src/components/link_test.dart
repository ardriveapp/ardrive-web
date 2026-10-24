import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(body: Center(child: child)),
        ),
      );

  Color colorOf(WidgetTester tester) => tester
      .widget<RichText>(find.descendant(
          of: find.byType(ArDriveLink), matching: find.byType(RichText)))
      .text
      .style!
      .color!;

  testWidgets('is underlined and runs its action when tapped', (tester) async {
    var taps = 0;
    await tester
        .pumpWidget(wrap(ArDriveLink(text: 'Learn more', onTap: () => taps++)));

    final style = tester
        .widget<RichText>(find.descendant(
            of: find.byType(ArDriveLink), matching: find.byType(RichText)))
        .text
        .style!;
    expect(style.decoration, TextDecoration.underline);

    await tester.tap(find.text('Learn more'));
    expect(taps, 1);
  });

  testWidgets('can be reached and opened with the keyboard', (tester) async {
    var taps = 0;
    await tester
        .pumpWidget(wrap(ArDriveLink(text: 'Learn more', onTap: () => taps++)));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('darkens on hover', (tester) async {
    final tokens = ArDriveColorTokens.darkMode();
    await tester
        .pumpWidget(wrap(ArDriveLink(text: 'Learn more', onTap: () {})));
    expect(colorOf(tester), tokens.textMid);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(ArDriveLink)));
    await tester.pump();

    expect(colorOf(tester), tokens.textHigh);
  });

  testWidgets('is announced as a link, or as a button for an action',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(wrap(ArDriveLink(text: 'Terms', onTap: () {})));
    expect(
        tester.getSemantics(find.byType(ArDriveLink)),
        matchesSemantics(
          label: 'Terms',
          isLink: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
        ));

    await tester.pumpWidget(
        wrap(ArDriveLink(text: 'Copy', onTap: () {}, isAction: true)));
    expect(
        tester.getSemantics(find.byType(ArDriveLink)),
        matchesSemantics(
          label: 'Copy',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
        ));

    handle.dispose();
  });

  testWidgets('an external link shows the new-window icon', (tester) async {
    await tester.pumpWidget(
        wrap(ArDriveLink(text: 'Docs', onTap: () {}, external: true)));
    expect(find.byIcon(ArDriveIconsData.new_window), findsOneWidget);
  });
}
