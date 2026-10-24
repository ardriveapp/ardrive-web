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

  testWidgets('needs only a title', (tester) async {
    await tester
        .pumpWidget(wrap(const ArDriveEmptyState(title: 'Nothing here')));

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.byType(ArDriveButtonNew), findsNothing);
  });
}
