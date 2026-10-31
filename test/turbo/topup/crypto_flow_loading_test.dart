import 'package:ardrive/turbo/topup/views/unified/unified_crypto_flow.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The spinner between crypto screens used to have no way out, so a flow
/// waiting on a lost wallet popup could only be left by reloading.
void main() {
  testWidgets('the crypto flow spinner can be closed', (tester) async {
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CryptoFlowLoading(onClose: () {}),
        ),
      ),
    ));

    expect(find.byType(ArDriveStandardModalNew), findsOneWidget);
    expect(
      tester
          .widget<ArDriveStandardModalNew>(find.byType(ArDriveStandardModalNew))
          .hasCloseButton,
      isTrue,
    );
  });
}
