import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A folded part of a dialog: one row saying what is set, its content under
/// it on request.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ArDriveApp(
        themeData: lightTheme(),
        builder: (context) => MaterialApp(
          home: Scaffold(body: Column(children: [child])),
        ),
      ),
    );
    await tester.pump();
  }

  const disclosure = ArDriveDisclosure(
    icon: Icons.tune,
    title: 'Options',
    summary: ['Compressed', 'No license'],
    child: Text('the options'),
  );

  testWidgets('starts folded, saying what is set', (tester) async {
    await pump(tester, disclosure);

    expect(find.text('Options'), findsOneWidget);
    expect(find.text('Compressed'), findsOneWidget);
    expect(find.text('No license'), findsOneWidget);
    expect(find.text('the options'), findsNothing);
    expect(tester.getSize(find.byType(ArDriveDisclosure)).height,
        ArDriveDisclosure.rowHeight);
  });

  testWidgets(
      'opens to its content, lined up with the title, and the '
      'summary makes way', (tester) async {
    await pump(tester, disclosure);

    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();

    expect(find.text('the options'), findsOneWidget);
    expect(find.text('Compressed'), findsNothing);
    expect(tester.getTopLeft(find.text('the options')).dx,
        tester.getTopLeft(find.text('Options')).dx);

    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(find.text('the options'), findsNothing);
  });

  testWidgets('opens from the keyboard, and says so to a screen reader',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, disclosure);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('the options'), findsOneWidget);
    final node = tester.getSemantics(find.text('Options'));
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.hasFlag(SemanticsFlag.hasExpandedState), isTrue);
    expect(node.hasFlag(SemanticsFlag.isExpanded), isTrue);
    semantics.dispose();
  });

  testWidgets('with a trailing widget it does not fold, and has no chevron',
      (tester) async {
    await pump(
      tester,
      ArDriveDisclosure(
        icon: Icons.sell_outlined,
        title: 'Give it a name',
        summary: const ['Optional'],
        trailing: ArDriveLink(text: 'Get a name', onTap: () {}),
      ),
    );

    expect(find.text('Get a name'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsNothing);
    await tester.tap(find.text('Give it a name'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ArDriveDisclosure)).height,
        ArDriveDisclosure.rowHeight);
  });

  testWidgets('two of them stack with their titles in line', (tester) async {
    await pump(
      tester,
      const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArDriveDisclosure(
            icon: Icons.sell_outlined,
            title: 'Give it a name like yours.ar.io',
            summary: ['Optional'],
            child: Text('names'),
          ),
          disclosure,
        ],
      ),
    );

    expect(
      tester.getTopLeft(find.text('Give it a name like yours.ar.io')).dx,
      tester.getTopLeft(find.text('Options')).dx,
    );
  });
}
