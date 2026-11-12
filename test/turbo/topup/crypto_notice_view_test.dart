import 'package:ardrive/turbo/topup/views/unified/crypto_notice_view.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Switching the wallet account before paying emitted a state with no screen,
/// leaving a spinner. The notice names what happened and offers a way out.
void main() {
  Future<void> pump(WidgetTester tester, CryptoNoticeView view) =>
      tester.pumpWidget(ArDriveApp(
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: view),
        ),
      ));

  testWidgets('shows the message and both actions work', (tester) async {
    var started = 0;
    var closed = 0;
    await pump(
      tester,
      CryptoNoticeView(
        title: 'Account changed',
        message: 'Your wallet switched accounts. Start again with the '
            'account you want to pay from.',
        actionTitle: 'Start again',
        onAction: () => started++,
        onClose: () => closed++,
      ),
    );

    expect(find.textContaining('Your wallet switched accounts'), findsOneWidget);

    await tester.tap(find.text('Start again'));
    expect(started, 1);

    await tester.tap(find.text('Close'));
    expect(closed, 1);
  });
}
