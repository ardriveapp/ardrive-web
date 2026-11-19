import 'package:ardrive/pages/shared_file/shared_file_identity.dart';
import 'package:ardrive/pages/shared_file/shared_file_locked_view.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The private file page's gate, as a private drive or folder page uses it
/// (docs/PUBLICATIONS.md, "Unlock screen").
void main() {
  late List<String> submitted;

  Future<void> pump(WidgetTester tester, SharedFileGate gate,
      {String? error}) async {
    submitted = [];
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SharedFileLockedView(
              gate: gate,
              controller: controller,
              errorMessage: error,
              onSubmit: submitted.add,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> typeAndOpen(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextFormField), text);
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a page says it is private, under its own frame', (tester) async {
    await pump(tester, SharedFileGate.page);

    expect(find.text('This page is private'), findsOneWidget);
    expect(
      find.text('The person who shared it sent you the key separately.'),
      findsOneWidget,
    );
    expect(find.text('Paste the access key'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    // The page's frame shows its icon and title; no file is named.
    expect(find.byType(SharedFileIdentity), findsNothing);
    expect(find.text('Remember this key for this tab'), findsOneWidget);
  });

  testWidgets('a page without a password still checks a key\'s shape',
      (tester) async {
    await pump(tester, SharedFileGate.page);
    await typeAndOpen(tester, 'hunter2');

    expect(submitted, isEmpty);
    expect(find.textContaining('43 characters'), findsOneWidget);
  });

  testWidgets('a page with a password takes any text', (tester) async {
    await pump(tester, SharedFileGate.pageWithPassword);

    expect(find.text('Access key or password'), findsOneWidget);
    expect(
      find.text(
          'The person who shared it sent you the key or password separately.'),
      findsOneWidget,
    );
    await typeAndOpen(tester, 'hunter2');

    expect(submitted, ['hunter2']);
    expect(find.textContaining('43 characters'), findsNothing);
  });

  testWidgets('what did not open it is said under the field, which keeps it',
      (tester) async {
    await pump(tester, SharedFileGate.pageWithPassword,
        error: 'That didn’t open this page.');

    expect(find.text('That didn’t open this page.'), findsOneWidget);
  });

  testWidgets('a shared file keeps its own gate', (tester) async {
    await pump(tester, SharedFileGate.file);

    expect(find.text('This page is private'), findsNothing);
    expect(find.byType(SharedFileIdentity), findsOneWidget);
    expect(find.text('Open'), findsNothing);
  });
}
