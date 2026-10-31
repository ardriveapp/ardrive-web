import 'package:ardrive/turbo/topup/views/topup_success_view.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the new balance is a figure in the text colour, not green',
      (tester) async {
    late ArDriveColorTokens colors;
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(builder: (context) {
            colors = ArDriveTheme.of(context).themeData.colorTokens;
            return const SingleChildScrollView(
              child: TurboSuccessView(
                amountPaid: '\$25.00',
                creditsReceived: '2.0712',
                newBalanceCredits: '10.9190 credits',
              ),
            );
          }),
        ),
      ),
    ));

    final balance = tester.widget<Text>(find.text('10.9190 credits'));
    expect(balance.style?.color, colors.textHigh);
    expect(balance.style?.color, isNot(colors.statusSuccessFg));
  });
}
