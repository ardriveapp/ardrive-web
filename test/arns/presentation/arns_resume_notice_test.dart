import 'package:ardrive/arns/presentation/resume/arns_resume_cubit.dart';
import 'package:ardrive/arns/presentation/resume/arns_resume_scope.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(WidgetTester tester, ArNSResumeNotice notice) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showArNSResumeNotice(context, notice),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
  }

  testWidgets('a change that went through says Name saved', (tester) async {
    await show(
      tester,
      const ArNSResumeNotice(
        outcome: ArNSResumeOutcome.saved,
        name: 'blog_acme',
        nonce: 'a1',
      ),
    );

    expect(find.text('Name saved: blog_acme.ar.io'), findsOneWidget);
  });

  testWidgets('one that failed says the credits come back', (tester) async {
    await show(
      tester,
      const ArNSResumeNotice(
        outcome: ArNSResumeOutcome.refunding,
        name: 'blog_acme',
        nonce: 'a1',
      ),
    );

    expect(
      find.text("The change to blog_acme.ar.io wasn't made. "
          'Your credits come back within 15 minutes.'),
      findsOneWidget,
    );
  });

  testWidgets('one that expired or awaited approval says it was not made',
      (tester) async {
    await show(
      tester,
      const ArNSResumeNotice(
        outcome: ArNSResumeOutcome.expired,
        name: 'blog_acme',
        nonce: 'a1',
      ),
    );

    expect(
      find.text("The change to blog_acme.ar.io wasn't approved in time, "
          "so it wasn't made. Your credits come back within 15 minutes."),
      findsOneWidget,
    );
    expect(find.byType(SnackBarAction), findsNothing);
  });
}
