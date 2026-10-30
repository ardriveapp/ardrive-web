import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every control is reachable by keyboard and shows a focus ring (README).
/// The menu buttons, dialog closes and icon buttons were not.
void main() {
  Widget app(Widget child) => ArDriveApp(
        builder: (context) => MaterialApp(home: Scaffold(body: child)),
      );

  bool ringShown(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .any((p) => p.foregroundPainter is ArDriveFocusRingPainter);

  testWidgets('Tab reaches it, Enter presses it, and the ring shows',
      (tester) async {
    var pressed = 0;
    await tester.pumpWidget(app(Center(
      child: ArDriveFocusable(
        onActivate: () => pressed++,
        child: const SizedBox.square(dimension: 24),
      ),
    )));
    expect(ringShown(tester), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ringShown(tester), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(pressed, 2);
  });

  testWidgets('without an action it is not a Tab stop', (tester) async {
    await tester.pumpWidget(app(const Center(
      child: ArDriveFocusable(
        onActivate: null,
        child: SizedBox.square(dimension: 24),
      ),
    )));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ringShown(tester), isFalse);
  });

  testWidgets(
      'a menu opens from the keyboard on its first item, Down moves, Enter '
      'picks, and focus goes back to its button', (tester) async {
    String? picked;
    await tester.pumpWidget(app(Center(
      child: ArDriveDropdown(
        height: 48,
        anchor: const Aligned(
          follower: Alignment.topRight,
          target: Alignment.bottomRight,
        ),
        items: [
          for (final name in ['Share drive', 'Hide', 'More info'])
            ArDriveDropdownItem(
              onClick: () => picked = name,
              content: SizedBox(height: 48, child: Text(name)),
            ),
        ],
        child: const SizedBox.square(dimension: 24, child: Text('menu')),
      ),
    )));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Hide'), findsOneWidget, reason: 'the menu is open');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(picked, 'Hide');
    expect(find.text('Hide'), findsNothing, reason: 'the menu closed');
    final focused = FocusManager.instance.primaryFocus;
    expect(focused?.debugLabel, 'menu button');
  });

  testWidgets(
      'Enter opens a menu inside a table that takes Enter for its own rows',
      (tester) async {
    // The drives table opens its selected row on Enter, from a Focus around
    // the rows. It heard Enter before the app's root mapped it, so a row's
    // menu button did nothing.
    var rowOpened = false;
    await tester.pumpWidget(app(Center(
      child: Focus(
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.enter) {
            rowOpened = true;
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ArDriveDropdown(
          height: 48,
          anchor: const Aligned(
            follower: Alignment.topRight,
            target: Alignment.bottomRight,
          ),
          items: [
            ArDriveDropdownItem(
              onClick: () {},
              content: const SizedBox(height: 48, child: Text('Hide')),
            ),
          ],
          child: const SizedBox.square(dimension: 24, child: Text('menu')),
        ),
      ),
    )));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Hide'), findsOneWidget);
    expect(rowOpened, isFalse);
  });

  testWidgets('a dialog\'s close can be reached and pressed from the keyboard',
      (tester) async {
    await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
        onPressed: () => showAnimatedDialog(
          context,
          content: const ArDriveStandardModalNew(
            title: 'Rename',
            hasCloseButton: true,
            description: 'A new name.',
          ),
        ),
        child: const Text('Open'),
      ),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ringShown(tester), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsNothing);
  });

  testWidgets('a field\'s error is a live region, so it is read out',
      (tester) async {
    await tester.pumpWidget(app(const ArDriveTextFieldNew(
      label: 'Password',
      errorMessage: 'Wrong password',
      showErrorMessage: true,
    )));
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(
      tester.getSemantics(find.text('Wrong password')),
      matchesSemantics(label: 'Wrong password', isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('a button shows the ring when Tab reaches it, not when clicked',
      (tester) async {
    var pressed = 0;
    await tester.pumpWidget(app(Center(
      child: Builder(
        builder: (context) => ArDriveButtonNew(
          text: 'Sync this drive',
          typography: ArDriveTypographyNew.of(context),
          onPressed: () => pressed++,
        ),
      ),
    )));
    await tester.tap(find.text('Sync this drive'));
    await tester.pump();
    expect(pressed, 1);
    expect(ringShown(tester), isFalse, reason: 'a click shows no ring');

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ringShown(tester), isTrue);
  });

  testWidgets('an item that opens a dialog keeps focus in the dialog',
      (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(app(Builder(builder: (context) {
      pageContext = context;
      return Center(
        child: ArDriveDropdown(
          height: 48,
          anchor: const Aligned(
            follower: Alignment.topRight,
            target: Alignment.bottomRight,
          ),
          items: [
            ArDriveDropdownItem(
              onClick: () => showAnimatedDialog(
                pageContext,
                // No autofocus, like most confirmations: the dialog's route
                // takes focus a beat after the menu closes.
                content: const ArDriveStandardModalNew(
                  title: 'Share drive',
                  description: 'Anyone with the link can see it.',
                ),
              ),
              content: const SizedBox(height: 48, child: Text('Share')),
            ),
          ],
          child: const SizedBox.square(dimension: 24, child: Text('menu')),
        ),
      );
    })));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Share drive'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('menu button'),
        reason: 'the menu button took focus from the dialog');
  });
}
