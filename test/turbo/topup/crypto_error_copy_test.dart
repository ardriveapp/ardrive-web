import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/views/unified/crypto_result_view.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockCryptoTopupBloc extends MockBloc<CryptoTopupEvent, CryptoTopupState>
    implements CryptoTopupBloc {}

/// The failure screen says what a failed crypto payment cost, as far as the
/// app can tell. It used to say "Your funds have not been charged." in every
/// case, including after a transaction had reached the network.
void main() {
  Future<void> pump(WidgetTester tester, CryptoTopupError state) async {
    final bloc = _MockCryptoTopupBloc();
    whenListen(bloc, const Stream<CryptoTopupState>.empty(),
        initialState: state);
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BlocProvider<CryptoTopupBloc>.value(
            value: bloc,
            child: CryptoErrorView(onRetry: () {}, onClose: () {}),
          ),
        ),
      ),
    ));
  }

  testWidgets('a payment declined in the wallet made no payment',
      (tester) async {
    await pump(
      tester,
      const CryptoTopupError(
        errorType: CryptoTopupErrorType.transactionRejected,
        message: 'User rejected the request.',
      ),
    );

    expect(find.text('No payment was made.'), findsOneWidget);
    expect(find.textContaining('not been charged'), findsNothing);
  });

  testWidgets('a transaction that failed on the network may have cost a fee',
      (tester) async {
    await pump(
      tester,
      const CryptoTopupError(
        errorType: CryptoTopupErrorType.transactionFailed,
        message: 'Transaction reverted.',
        txId: '5VERv8NMabcdefghijklmnopqrstuvwxyzjF3ZpRzr',
      ),
    );

    expect(find.textContaining('may have paid a network fee'), findsOneWidget);
    expect(find.text('No payment was made.'), findsNothing);
  });

  testWidgets('without a transaction, it asks to check the wallet first',
      (tester) async {
    await pump(
      tester,
      const CryptoTopupError(
        errorType: CryptoTopupErrorType.transactionFailed,
        message: 'Transaction submitted but no transaction ID received',
      ),
    );

    expect(
      find.text("Check your wallet before trying again, so you don't pay "
          'twice.'),
      findsOneWidget,
    );
  });
}
