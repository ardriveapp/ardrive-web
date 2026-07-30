import 'package:ardrive/components/turbo_free_status_message.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(FreeUploadStatus status) {
    return ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', '')],
        home: Scaffold(
          body: TurboFreeStatusMessage(status: status),
        ),
      ),
    );
  }

  testWidgets('free shows the free-transaction message', (tester) async {
    await tester.pumpWidget(wrap(FreeUploadStatus.free));
    await tester.pumpAndSettle();

    expect(find.textContaining('free thanks to Turbo'), findsOneWidget);
  });

  testWidgets('exceedsAllowance explains the upload is bigger than the pool',
      (tester) async {
    await tester.pumpWidget(wrap(FreeUploadStatus.exceedsAllowance));
    await tester.pumpAndSettle();

    expect(find.textContaining('exceeds your free allowance'), findsOneWidget);
    // It must NOT claim the tier is used up — the user still has allowance.
    expect(find.textContaining('used up'), findsNothing);
  });

  testWidgets('allowanceUsedUp says the free tier is used up', (tester) async {
    await tester.pumpWidget(wrap(FreeUploadStatus.allowanceUsedUp));
    await tester.pumpAndSettle();

    expect(find.textContaining('Free allowance used up'), findsOneWidget);
  });

  testWidgets('notEligible renders nothing at all', (tester) async {
    await tester.pumpWidget(wrap(FreeUploadStatus.notEligible));
    await tester.pumpAndSettle();

    expect(find.byType(Text), findsNothing);
  });
}
