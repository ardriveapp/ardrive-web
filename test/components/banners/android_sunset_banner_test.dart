import 'package:ardrive/components/banners/android_sunset_banner.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders banner copy', (tester) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: AndroidSunsetBanner(
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining(
        'The ArDrive Android app is being sunset.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Learn more',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('invokes dismissal callback on close', (tester) async {
    var dismissed = false;

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: AndroidSunsetBanner(
              onDismiss: () {
                dismissed = true;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(dismissed, isTrue);
  });
}
