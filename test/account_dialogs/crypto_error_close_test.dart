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

/// A failed payment with nothing to retry ends in a plain Close, not a red
/// primary button.
void main() {
  Future<void> pump(WidgetTester tester, bool canRetry) async {
    final bloc = _MockCryptoTopupBloc();
    whenListen(bloc, const Stream<CryptoTopupState>.empty(),
        initialState: CryptoTopupError(
          errorType: CryptoTopupErrorType.transactionRejected,
          message: 'User rejected the request.',
          canRetry: canRetry,
        ));
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

  testWidgets('with nothing to retry, Close is a secondary button',
      (tester) async {
    await pump(tester, false);

    final close = tester.widget<ArDriveButtonNew>(
        find.widgetWithText(ArDriveButtonNew, 'Close').last);
    expect(close.variant, ButtonVariant.secondary);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('with a retry, Try again is the primary', (tester) async {
    await pump(tester, true);

    final retry = tester.widget<ArDriveButtonNew>(
        find.widgetWithText(ArDriveButtonNew, 'Try again'));
    expect(retry.variant, ButtonVariant.primary);
  });
}
