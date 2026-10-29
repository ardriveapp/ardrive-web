import 'dart:async';

import 'package:ardrive/components/wander_unavailable_dialog.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  bool? answer;

  Future<void> open(
    WidgetTester tester,
    ArConnectUnavailableReason reason, {
    Future<void>? answered,
  }) async {
    answer = null;
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en', '')],
          home: ChangeNotifierProvider<ActivityTracker>.value(
            value: ActivityTracker(),
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => answer = await askToRetryWander(
                    context,
                    reason,
                    answered: answered,
                  ),
                  child: const Text('write'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('write'));
    await tester.pumpAndSettle();
  }

  testWidgets('a locked Wander says to unlock it, and Try again tries again',
      (tester) async {
    await open(tester, ArConnectUnavailableReason.noAnswer);

    expect(find.text("Wander didn't answer"), findsOneWidget);
    expect(find.text('Unlock Wander, then try again.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(answer, isTrue);
  });

  testWidgets('Cancel gives up', (tester) async {
    await open(tester, ArConnectUnavailableReason.noAnswer);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(answer, isFalse);
  });

  testWidgets('a missing Wander says so', (tester) async {
    await open(tester, ArConnectUnavailableReason.notInstalled);

    expect(find.text("Wander isn't available"), findsOneWidget);
    expect(find.textContaining('Install or turn on Wander'), findsOneWidget);
  });

  testWidgets('closes itself when Wander answers after all', (tester) async {
    final answered = Completer<void>();
    await open(
      tester,
      ArConnectUnavailableReason.noAnswer,
      answered: answered.future,
    );
    expect(find.text("Wander didn't answer"), findsOneWidget);

    answered.complete();
    await tester.pumpAndSettle();

    expect(find.text("Wander didn't answer"), findsNothing);
    expect(answer, isTrue);
  });
}
