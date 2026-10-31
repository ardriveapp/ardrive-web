import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_balance/turbo_balance_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// A balance that failed to load used to read "0.0000", the same as an empty
/// account.
void main() {
  Future<void> pump(
    WidgetTester tester,
    TurboBalanceState state, {
    VoidCallback? onRetry,
  }) async {
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ProfileCreditsValue(state: state, onRetry: onRetry ?? () {}),
        ),
      ),
    ));
  }

  testWidgets('an error is not shown as 0.0000, and can be retried',
      (tester) async {
    var retried = 0;
    await pump(tester, TurboBalanceErrorState(), onRetry: () => retried++);

    expect(find.text('0.0000'), findsNothing);
    expect(find.text('Could not load'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, 1);
  });

  testWidgets('loading is a spinner, not dots', (tester) async {
    await pump(tester, TurboBalanceLoading());

    expect(find.text('...'), findsNothing);
    expect(find.byKey(const Key('profileCreditsLoading')), findsOneWidget);
  });

  testWidgets('a read balance is shown as a number', (tester) async {
    await pump(
      tester,
      TurboBalanceSuccessState(balance: BigInt.from(1500000000000)),
    );

    expect(find.byKey(const Key('profileCreditsBalance')), findsOneWidget);
    expect(find.text('Could not load'), findsNothing);
  });
}
