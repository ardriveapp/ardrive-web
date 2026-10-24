import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Modal widget and its contents render', (tester) async {
    const modal = ArDriveModal(
      content: Text('Some widget'),
      constraints: BoxConstraints(
        maxHeight: 100,
        maxWidth: 100,
      ),
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(home: modal),
      ),
    );

    expect(find.byWidget(modal), findsOneWidget);
    expect(find.text('Some widget'), findsOneWidget);
  });

  testWidgets('ArDriveMiniModal widget and its contents render',
      (tester) async {
    const modal = ArDriveMiniModal(
      content: 'Content',
      title: 'Title',
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(home: modal),
      ),
    );

    expect(find.byWidget(modal), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('ArDriveIconModal widget and its contents render',
      (tester) async {
    const modal = ArDriveIconModal(
      content: 'Content',
      title: 'Title',
      icon: Icon(Icons.abc),
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(home: modal),
      ),
    );

    expect(find.byWidget(modal), findsOneWidget);
    expect(find.byType(Icon), findsWidgets); // icon and the close icon
    expect(find.text('Content'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('ArDriveLongModal widget and its contents render',
      (tester) async {
    const modal = ArDriveLongModal(
      content: 'Content',
      title: 'Title',
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(home: modal),
      ),
    );

    expect(find.byWidget(modal), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('ArDriveStandardModal widget and its contents render',
      (tester) async {
    bool varToChange = false;

    final modal = ArDriveStandardModal(
      description: 'Content',
      title: 'Title',
      actions: [
        ModalAction(
          action: () {
            // just to validate if the callback is calleds
            varToChange = true;
          },
          title: 'Title',
        ),
      ],
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(home: modal),
      ),
    );

    // taps the action inside the modal
    await tester.tap(find.byType(ArDriveButton));

    expect(find.byWidget(modal), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
    expect(find.text('Title'), findsNWidgets(2));
    // verify if the variable was changed
    expect(varToChange, true);
  });

  testWidgets(
      'ArDriveStandardModal should render only content when content and description is provided',
      (tester) async {
    const testWidget = _TestWidget();

    final modal = ArDriveStandardModal(
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
      'ArDriveStandardModal should render description wehn provided and content is null',
      (tester) async {
    const testWidget = _TestWidget();

    final modal = ArDriveStandardModal(
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
}

class _TestWidget extends StatelessWidget {
  const _TestWidget();

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
