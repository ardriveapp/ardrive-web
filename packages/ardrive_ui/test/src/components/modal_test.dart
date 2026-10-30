import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'ArDriveStandardModalNew shows only the content when it has content and a description',
      (tester) async {
    const testWidget = _TestWidget();

    final modal = ArDriveStandardModalNew(
      description: 'Content',
      content: testWidget,
      title: 'Title',
      actions: [
        ModalAction(
          action: () {},
          title: 'Title',
        ),
      ],
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(home: modal),
      ),
    );

    expect(find.byWidget(testWidget), findsOneWidget);
  });

  testWidgets(
      'ArDriveStandardModalNew shows the description when there is no content',
      (tester) async {
    const testWidget = _TestWidget();

    final modal = ArDriveStandardModalNew(
      description: 'Description',
      content: null,
      title: 'Title',
      actions: [
        ModalAction(
          action: () {},
          title: 'Title',
        ),
      ],
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(home: modal),
      ),
    );

    expect(find.byWidget(testWidget), findsNothing);
    expect(find.text('Description'), findsOneWidget);
  });
  testWidgets(
      'ArDriveStandardModalNew with scrollableContent keeps its action '
      'reachable on a short screen', (tester) async {
    // A short, mobile-height viewport where a tall modal would otherwise push
    // its actions off the bottom.
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var tapped = false;

    final modal = ArDriveStandardModalNew(
      scrollableContent: true,
      title: 'Network congestion',
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            40,
            (i) => Text('Congestion warning line $i'),
          ),
        ),
      ),
      actions: [
        ModalAction(action: () => tapped = true, title: 'Proceed'),
      ],
    );

    await tester.pumpWidget(
      ArDriveApp(builder: (context) => MaterialApp(home: modal)),
    );

    // The modal's own body scrolls (scoped to the modal so an unrelated
    // ancestor scroll view can't make this pass)...
    expect(
      find.descendant(
        of: find.byType(ArDriveStandardModalNew),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );

    // ...and the action, though below the fold, can be scrolled to and tapped.
    await tester.ensureVisible(find.text('Proceed'));
    await tester.tap(find.text('Proceed'));
    expect(tapped, isTrue);
  });

  testWidgets(
      'ArDriveStandardModalNew without scrollableContent still renders content '
      'and actions (default behaviour unchanged)', (tester) async {
    const testWidget = _TestWidget();

    final modal = ArDriveStandardModalNew(
      title: 'Title',
      content: testWidget,
      actions: [
        ModalAction(action: () {}, title: 'Ok'),
      ],
    );

    await tester.pumpWidget(
      ArDriveApp(builder: (context) => MaterialApp(home: modal)),
    );

    expect(find.byWidget(testWidget), findsOneWidget);
    expect(find.text('Ok'), findsOneWidget);
    // Default path adds no scroll view around the body — the branch is distinct.
    expect(
      find.descendant(
        of: find.byType(ArDriveStandardModalNew),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'ArDriveStandardModalNew makes a lone action primary unless it names '
      'a variant', (tester) async {
    Future<ButtonVariant> variantOf(ModalAction action) async {
      await tester.pumpWidget(
        ArDriveApp(
          builder: (context) => MaterialApp(
            home: ArDriveStandardModalNew(title: 'Title', actions: [action]),
          ),
        ),
      );

      return tester
          .widget<ArDriveButtonNew>(find.byType(ArDriveButtonNew))
          .variant;
    }

    expect(
      await variantOf(ModalAction(action: () {}, title: 'Ok')),
      ButtonVariant.primary,
    );
    expect(
      await variantOf(
        ModalAction(
          action: () {},
          title: 'Cancel',
          variant: ButtonVariant.secondary,
        ),
      ),
      ButtonVariant.secondary,
    );
  });

  testWidgets(
      'ArDriveStandardModalNew keeps short labels at the usual widths and '
      'widens a button to fit a long one', (tester) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: ArDriveStandardModalNew(
            title: 'Title',
            width: 800,
            actions: [
              ModalAction(action: () {}, title: 'No'),
              ModalAction(action: () {}, title: 'Ok'),
              ModalAction(action: () {}, title: 'Upload as new versions'),
            ],
          ),
        ),
      ),
    );

    final buttons = tester
        .widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew))
        .toList();

    expect(buttons[0].maxWidth, 100);
    expect(buttons[1].maxWidth, 110);
    expect(buttons[2].maxWidth, greaterThan(110));

    // The long label is drawn on one line, as tall as the short one.
    final longLabel = tester.getSize(find.text('Upload as new versions'));
    final shortLabel = tester.getSize(find.text('Ok'));
    expect(longLabel.height, shortLabel.height);
  });

  /// A lone Cancel was drawn as a red primary button, as if cancelling were
  /// the thing the dialog was for.
  testWidgets('ArDriveStandardModalNew keeps a lone dismiss action secondary',
      (tester) async {
    var closed = false;
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: ArDriveStandardModalNew(title: 'Choose an image', actions: [
            ModalAction.dismiss(action: () => closed = true, title: 'Cancel'),
          ]),
        ),
      ),
    );

    final button =
        tester.widget<ArDriveButtonNew>(find.byType(ArDriveButtonNew));
    expect(button.variant, ButtonVariant.secondary);
    expect(button.isDisabled, isFalse);

    await tester.tap(find.text('Cancel'));
    expect(closed, isTrue);
  });

  /// The first action was drawn without its enabled state, so a disabled
  /// first action could still be pressed. Every action honours it now.
  testWidgets('ArDriveStandardModalNew disables any action that is not enabled',
      (tester) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: ArDriveStandardModalNew(title: 'Title', actions: [
            ModalAction(action: () {}, title: 'First', isEnable: false),
            ModalAction(action: () {}, title: 'Second', isEnable: false),
          ]),
        ),
      ),
    );

    final buttons =
        tester.widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew));
    expect(buttons.map((b) => b.isDisabled), [true, true]);
    expect(buttons.map((b) => b.size), everyElement(ArDriveButtonSize.regular),
        reason: 'dialog actions are the regular height');
  });

  /// The close button was an unlabelled icon: a screen reader said nothing
  /// about what it does.
  testWidgets('ArDriveStandardModalNew names its close button', (tester) async {
    final handle = tester.ensureSemantics();
    var closed = 0;

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: ArDriveStandardModalNew(
              title: 'Buy Turbo Credits',
              hasCloseButton: true,
              close: () => closed++,
              content: const Text('Content'),
            ),
          ),
        ),
      ),
    );

    final close = find.bySemanticsLabel('Close');
    expect(close, findsOneWidget);
    expect(
      tester.getSemantics(close),
      matchesSemantics(isButton: true, hasTapAction: true, label: 'Close'),
    );

    await tester.tap(close);
    expect(closed, 1);
    handle.dispose();
  });

  Future<double> dialogWidthAt(WidgetTester tester, Size screen) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAnimatedDialog(
                  context,
                  content: const ArDriveStandardModalNew(
                    title: 'Rename',
                    description: 'A new name for the file.',
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return tester.getSize(find.byType(ArDriveModalNew)).width;
  }

  // Under the tablet breakpoint a dialog fills the width less a 16 px
  // gutter. It was a 310 px card on a 390 px phone: Flutter's 40 px inset
  // and the 350 cap.
  testWidgets('on a phone a dialog fills the width less 16 a side',
      (tester) async {
    expect(await dialogWidthAt(tester, const Size(390, 844)), 390 - 32);
  });

  testWidgets('a small phone gives the card its full width, no gutter',
      (tester) async {
    // A 320 by 568 phone has no room for one: the drive state dialog's
    // content overflowed at 288.
    expect(await dialogWidthAt(tester, const Size(320, 568)),
        greaterThan(320 - 32));
  });

  testWidgets('a phone on its side keeps the standard card', (tester) async {
    // It doesn't stretch a dialog across an 800 px wide, 375 high screen.
    expect(await dialogWidthAt(tester, const Size(812, 375)),
        lessThanOrEqualTo(350));
  });

  testWidgets('on a desktop a dialog keeps its width', (tester) async {
    expect(await dialogWidthAt(tester, const Size(1440, 900)),
        lessThanOrEqualTo(350));
  });
}

class _TestWidget extends StatelessWidget {
  const _TestWidget();

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
