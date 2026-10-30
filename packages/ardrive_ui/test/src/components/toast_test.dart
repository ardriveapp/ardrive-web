import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showToast(
    WidgetTester tester, {
    required ArDriveStatusType type,
    String? actionLabel,
    VoidCallback? onAction,
  }) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showArDriveToast(
                  ScaffoldMessenger.of(context),
                  text: 'Could not sync',
                  type: type,
                  actionLabel: actionLabel,
                  onAction: onAction,
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
  }

  testWidgets('an error toast carries the error icon and colours',
      (tester) async {
    await showToast(tester, type: ArDriveStatusType.error);
    final tokens = ArDriveColorTokens.darkMode();
    expect(find.text('Could not sync'), findsOneWidget);
    expect(find.byIcon(ArDriveIcons.closeCircle().icon), findsOneWidget);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        tokens.statusErrorContainer);
  });

  testWidgets('a neutral toast has no icon', (tester) async {
    await showToast(tester, type: ArDriveStatusType.neutral);
    expect(find.byIcon(ArDriveIcons.closeCircle().icon), findsNothing);
    expect(find.byIcon(ArDriveIcons.checkmark().icon), findsNothing);
  });

  testWidgets('its action runs and closes the toast', (tester) async {
    var retried = false;
    await showToast(
      tester,
      type: ArDriveStatusType.error,
      actionLabel: 'Try again',
      onAction: () => retried = true,
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(retried, isTrue);
    expect(find.text('Could not sync'), findsNothing);
  });
}
