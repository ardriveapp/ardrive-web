import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/views/unified/crypto_processing_view.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockCryptoTopupBloc extends MockBloc<CryptoTopupEvent, CryptoTopupState>
    implements CryptoTopupBloc {}

void main() {
  testWidgets('the processing dialog has a title and announces its step',
      (tester) async {
    final handle = tester.ensureSemantics();
    final bloc = _MockCryptoTopupBloc();
    whenListen(
      bloc,
      const Stream<CryptoTopupState>.empty(),
      initialState: const CryptoTopupProcessing(
        token: CryptoToken.ethBase,
        estimatedTime: Duration(minutes: 1),
        isSubmitting: true,
      ),
    );
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
            child: const CryptoProcessingView(),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Payment in progress'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Approve the payment in your wallet'),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('while the wallet asks, it says how to cancel', (tester) async {
    final bloc = _MockCryptoTopupBloc();
    whenListen(
      bloc,
      const Stream<CryptoTopupState>.empty(),
      initialState: const CryptoTopupProcessing(
        token: CryptoToken.ethBase,
        estimatedTime: Duration(minutes: 1),
        isSubmitting: true,
      ),
    );
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
            child: const CryptoProcessingView(),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(
      find.textContaining('To cancel, reject the request in your wallet.'),
      findsOneWidget,
    );
  });
}
