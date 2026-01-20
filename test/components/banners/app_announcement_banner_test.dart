import 'package:ardrive/components/banners/app_announcement_banner.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders banner with message', (tester) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: AppAnnouncementBanner(
              message: 'Test announcement message.',
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining(
        'Test announcement message.',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders banner with message and url', (tester) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: AppAnnouncementBanner(
              message: 'Test announcement message.',
              url: 'https://example.com',
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining(
        'Test announcement message.',
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

  testWidgets('renders banner with custom url text', (tester) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: AppAnnouncementBanner(
              message: 'Test announcement message.',
              url: 'https://example.com',
              urlText: 'Click here',
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining(
        'Click here',
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
            body: AppAnnouncementBanner(
              message: 'Test announcement message.',
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
