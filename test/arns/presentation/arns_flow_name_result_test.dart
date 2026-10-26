import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // After uploading a file with a name on devnet, "Name saved" stood 600 px
  // tall and empty: the name took the whole row and the caption beside it
  // was laid out a letter wide.
  testWidgets('a real-length name wraps and the caption reads in one line',
      (tester) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: ArNSFlowNameResult(
                  outcome: ArNSFlowOutcome(
                    live: ['upload-one_ardrive-e2e-791j1aooiy6l5i'],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final caption = find.text('Live within about 5 minutes.');
    expect(caption, findsOneWidget);
    expect(tester.getSize(caption).width, greaterThan(150));
    expect(
        tester.getSize(find.byType(ArNSFlowNameResult)).height, lessThan(120));
  });
}
