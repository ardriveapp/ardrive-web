import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => ArDriveApp(
        builder: (context) => MaterialApp(home: Scaffold(body: child)),
      );

  testWidgets('shows its icon, title, message and actions', (tester) async {
    var created = false;
    var imported = false;
    await tester.pumpWidget(wrap(ArDriveEmptyState(
      icon: ArDriveIcons.folderOutline(),
      title: 'No drives yet',
      message: 'Create a drive to start uploading.',
      actionLabel: 'Create drive',
      onAction: () => created = true,
      secondaryActionLabel: 'Attach drive',
      onSecondaryAction: () => imported = true,
    )));

    expect(find.text('No drives yet'), findsOneWidget);
    expect(find.text('Create a drive to start uploading.'), findsOneWidget);

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.size, 32);
    expect(icon.color, ArDriveColorTokens.darkMode().iconLow);

    final buttons =
        tester.widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew));
    expect(buttons.map((b) => b.variant),
        [ButtonVariant.secondary, ButtonVariant.primary],
        reason: 'the main action is primary and comes last');

    await tester.tap(find.text('Create drive'));
    await tester.tap(find.text('Attach drive'));
    expect(created, isTrue);
    expect(imported, isTrue);
  });

  testWidgets('an action without a callback is drawn as unavailable',
      (tester) async {
    // ArDriveButtonNew colours itself off `isDisabled` alone, so a null
    // callback on its own would leave a button that looks live and does
    // nothing.
    await tester.pumpWidget(wrap(const ArDriveEmptyState(
      title: 'Busy',
      actionLabel: 'Sync',
      secondaryActionLabel: 'Sync all',
    )));

    final buttons =
        tester.widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew));
    expect(buttons.map((b) => b.isDisabled), [true, true]);
    expect(buttons.map((b) => b.onPressed), [null, null]);
  });

  testWidgets('an action with a callback is live', (tester) async {
    await tester.pumpWidget(wrap(ArDriveEmptyState(
      title: 'Idle',
      actionLabel: 'Sync',
      onAction: () {},
      secondaryActionLabel: 'Sync all',
      onSecondaryAction: () {},
    )));

    final buttons =
        tester.widgetList<ArDriveButtonNew>(find.byType(ArDriveButtonNew));
    expect(buttons.map((b) => b.isDisabled), [false, false]);
  });

  testWidgets('needs only a title', (tester) async {
    await tester
        .pumpWidget(wrap(const ArDriveEmptyState(title: 'Nothing here')));

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.byType(ArDriveButtonNew), findsNothing);
  });

  testWidgets('a framed state fills its space inside a dashed frame',
      (tester) async {
    await tester.pumpWidget(wrap(const Column(children: [
      Expanded(child: ArDriveEmptyState(title: 'Drop files', framed: true)),
    ])));

    expect(find.text('Drop files'), findsOneWidget);
    final size = tester.getSize(find.byType(ArDriveEmptyState));
    expect(size.height,
        tester.view.physicalSize.height / tester.view.devicePixelRatio);
  });

  testWidgets('an external action carries the new-window icon', (tester) async {
    await tester.pumpWidget(wrap(ArDriveEmptyState(
      title: 'No names yet',
      actionLabel: 'Get a name',
      onAction: () {},
      actionIsExternal: true,
    )));
    expect(find.byIcon(ArDriveIcons.newWindow().icon), findsOneWidget);
  });

  testWidgets('a footnote is one muted line under the actions', (tester) async {
    await tester.pumpWidget(wrap(ArDriveEmptyState(
      title: 'Drop files',
      actionLabel: 'Upload',
      onAction: () {},
      footnote: 'Small files upload free.',
    )));

    final line = find.text('Small files upload\u00A0free.');
    expect(line, findsOneWidget);
    expect(tester.getTopLeft(line).dy,
        greaterThan(tester.getBottomLeft(find.text('Upload')).dy));
    expect(tester.widget<Text>(line).style!.color,
        ArDriveColorTokens.darkMode().textMid);
  });

  testWidgets('a footnote keeps its last two words on one line',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap(const ArDriveEmptyState(
      title: 'Drop files',
      footnote: 'Small files upload free while it lasts.',
    )));

    expect(find.text('Small files upload free while it\u00A0lasts.'),
        findsOneWidget);
    expect(find.bySemanticsLabel('Small files upload free while it lasts.'),
        findsOneWidget,
        reason: 'read with plain spaces');
    handle.dispose();
  });

  test('keepLastWordsTogether joins only the last two words', () {
    expect(keepLastWordsTogether('a b c'), 'a b\u00A0c');
    expect(keepLastWordsTogether('one'), 'one');
    expect(keepLastWordsTogether(''), '');
  });
}
