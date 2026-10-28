@Tags(['measurement'])
library;

// Screenshots of the Turbo top-up's screens on the design system, for review.
// Several of them (the crypto confirmation, processing and result screens)
// can't be reached in a browser without a wallet extension. Not an assertion:
// run with
// flutter test test/turbo/topup_screens_test.dart --run-skipped --tags=measurement
// and find the PNGs in build/topup-shots.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:ardrive/turbo/services/solana_wallet_service.dart';
import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_quote.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/views/topup_success_view.dart';
import 'package:ardrive/turbo/topup/views/unified/crypto_confirmation_view.dart';
import 'package:ardrive/turbo/topup/views/unified/crypto_processing_view.dart';
import 'package:ardrive/turbo/topup/views/unified/crypto_result_view.dart';
import 'package:ardrive/turbo/topup/views/unified/wallet_connection_view.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

final _outDir = Directory('build/topup-shots');

class _MockCryptoTopupBloc extends MockBloc<CryptoTopupEvent, CryptoTopupState>
    implements CryptoTopupBloc {}

Future<ByteData> _read(String path) async =>
    ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);

Future<void> _loadFonts() async {
  const dir = 'packages/ardrive_ui/assets/fonts';
  final wavehaus = FontLoader('packages/ardrive_ui/Wavehaus');
  for (final f in [
    'Wavehaus-42Light.otf',
    'Wavehaus-66Book.otf',
    'Wavehaus-95SemiBold.otf',
    'Wavehaus-128Bold.otf',
    'Wavehaus-158ExtraBold.otf',
  ]) {
    wavehaus.addFont(_read('$dir/$f'));
  }
  await wavehaus.load();
  await (FontLoader('packages/ardrive_ui/ArDriveIcons')
        ..addFont(_read('$dir/ArDriveIcons.ttf')))
      .load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  await (FontLoader('MaterialIcons')
        ..addFont(_read(
            '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf')))
      .load();
  ArDriveMonospace.readFont = () => _read('$dir/mono/RobotoMono-Regular.ttf');
  await ArDriveMonospace.ensureLoaded();
}

// Made-up addresses and IDs of the right shape, not anyone's.
const _solAddress = '7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU';
const _ethAddress = '0x52908400098527886E0F7030069857D2E4169EE7';
const _txId =
    '5VERv8NMvzbJMEkV8xnrLkEaWRtSz9CosKDYjCJjBRnbJLgp8uirBgmQpjKhoR4tjF3ZpRzr';

CryptoQuote _quote(CryptoToken token, BigInt tokenAmount) => CryptoQuote(
      token: token,
      tokenAmount: tokenAmount,
      wincAmount: BigInt.parse('942400000000'),
      creditsDisplay: 0.9424,
      estimatedStorageGiB: 0.0623,
      usdValue: 5.14,
      networkFeeUsd: 0.01,
      expiresAt: DateTime.now().add(const Duration(minutes: 9)),
    );

CryptoTopupConfirmation _confirmation({required bool wrongNetwork}) =>
    wrongNetwork
        ? CryptoTopupConfirmation(
            token: CryptoToken.usdcBase,
            quote: _quote(CryptoToken.usdcBase, BigInt.from(5140000)),
            fromAddress: _ethAddress,
            toAddress: _ethAddress,
            networkState: NetworkState.needsSwitch,
            currentChainId: 1,
            currentTurboBalance: BigInt.parse('8840000000000'),
            currentBalanceStorage: '598.7 MB',
            newBalanceStorage: '662.5 MB',
            tokenBalance: 42.5,
          )
        : CryptoTopupConfirmation(
            token: CryptoToken.sol,
            quote: _quote(CryptoToken.sol, BigInt.from(50000000)),
            fromAddress: _solAddress,
            toAddress: _solAddress,
            networkState: NetworkState.correct,
            currentTurboBalance: BigInt.parse('8840000000000'),
            currentBalanceStorage: '598.7 MB',
            newBalanceStorage: '662.5 MB',
            tokenBalance: 1.2,
          );

void main() {
  setUpAll(_loadFonts);

  Future<void> capture(
    WidgetTester tester,
    String name,
    Widget Function(BuildContext context) build, {
    required bool phone,
    required bool dark,
    CryptoTopupState? state,
    double? height,
  }) async {
    final size = phone ? Size(390, height ?? 844) : Size(1100, height ?? 900);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    addTearDown(tester.view.reset);

    final bloc = _MockCryptoTopupBloc();
    final initial = state ?? const CryptoTopupInitial();
    whenListen(bloc, const Stream<CryptoTopupState>.empty(),
        initialState: initial);
    when(() => bloc.detectSolanaProviders())
        .thenReturn(const SolanaProviderDetection());

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ArDriveApp(
          themeData: dark ? null : lightTheme(),
          builder: (context) => MaterialApp(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ArDriveTheme.of(context).themeData.materialThemeData,
            home: BlocProvider<CryptoTopupBloc>.value(
              value: bloc,
              child: Builder(builder: build),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
          '${_outDir.path}/$name-${phone ? '390' : 'desktop'}-${dark ? 'dark' : 'light'}.png');
      file.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });

    // Confetti runs on timers: let them finish once the screen is gone.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }

  /// [child], a dialog, over the page.
  Widget dialog(BuildContext context, Widget child, {required bool phone}) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Scaffold(
      backgroundColor: colors.containerL0,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: colors.primitives.transparent900_64),
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.all(phone ? 12 : 24),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  for (final dark in [false, true]) {
    for (final phone in [false, true]) {
      final suffix =
          '${phone ? 'phone' : 'desktop'} ${dark ? 'dark' : 'light'}';

      testWidgets('crypto confirmation, $suffix', (tester) async {
        await capture(
          tester,
          'crypto-confirmation',
          (context) => dialog(
            context,
            CryptoConfirmationView(onBack: () {}, onClose: () {}),
            phone: phone,
          ),
          state: _confirmation(wrongNetwork: false),
          phone: phone,
          dark: dark,
        );
      });

      testWidgets('crypto confirmation, wrong network, $suffix',
          (tester) async {
        await capture(
          tester,
          'crypto-confirmation-wrong-network',
          (context) => dialog(
            context,
            CryptoConfirmationView(onBack: () {}, onClose: () {}),
            phone: phone,
          ),
          state: _confirmation(wrongNetwork: true),
          phone: phone,
          dark: dark,
        );
      });

      testWidgets('crypto processing, $suffix', (tester) async {
        await capture(
          tester,
          'crypto-processing',
          (context) =>
              dialog(context, const CryptoProcessingView(), phone: phone),
          state: const CryptoTopupProcessing(
            token: CryptoToken.sol,
            txId: _txId,
          ),
          phone: phone,
          dark: dark,
        );
      });

      testWidgets('crypto success, $suffix', (tester) async {
        await capture(
          tester,
          'crypto-success',
          (context) => dialog(
            context,
            CryptoSuccessView(onDone: () {}),
            phone: phone,
          ),
          state: CryptoTopupSuccess(
            txId: _txId,
            creditsAdded: BigInt.parse('942400000000'),
            newBalance: BigInt.parse('9782400000000'),
            token: CryptoToken.sol,
            tokenAmountSpent: 0.05,
            usdValue: 5.14,
            storageEstimate: '63.8 MB',
            newBalanceStorage: '662.5 MB',
          ),
          phone: phone,
          dark: dark,
        );
      });

      testWidgets('crypto error, $suffix', (tester) async {
        await capture(
          tester,
          'crypto-error',
          (context) => dialog(
            context,
            CryptoErrorView(onRetry: () {}, onClose: () {}),
            phone: phone,
          ),
          state: const CryptoTopupError(
            errorType: CryptoTopupErrorType.transactionFailed,
            message: 'The transaction was not confirmed on the network.',
            canRetry: true,
            token: CryptoToken.sol,
          ),
          phone: phone,
          dark: dark,
        );
      });

      testWidgets('wallet connection, no wallets, $suffix', (tester) async {
        await capture(
          tester,
          'wallet-no-wallets',
          (context) => dialog(
            context,
            WalletConnectionView(
              token: CryptoToken.sol,
              fiatAmount: 5.14,
              onBack: () {},
              onCancel: () {},
            ),
            phone: phone,
          ),
          state: const CryptoTopupWalletConnection(
            token: CryptoToken.sol,
            walletType: WalletType.solana,
          ),
          phone: phone,
          dark: dark,
        );
      });

      testWidgets('wallet not installed, $suffix', (tester) async {
        await capture(
          tester,
          'wallet-not-installed',
          (context) => dialog(
            context,
            WalletConnectionView(
              token: CryptoToken.sol,
              fiatAmount: 5.14,
              onBack: () {},
              onCancel: () {},
            ),
            phone: phone,
          ),
          state: const CryptoTopupWalletNotInstalled(
            token: CryptoToken.sol,
            walletType: WalletType.solana,
            installUrl: 'https://phantom.app/download',
          ),
          phone: phone,
          dark: dark,
        );
      });

      // SuccessView rather than TurboSuccessView, which always plays
      // confetti; the strings are TurboSuccessView's own.
      testWidgets('card success, $suffix', (tester) async {
        await capture(
          tester,
          'card-success',
          (context) => dialog(
            context,
            SuccessView(
              successMessage: appLocalizationsOf(context).paymentSuccessful,
              detailMessage: appLocalizationsOf(context)
                  .yourCreditsWillBeAddedToYourAccount,
              closeButtonLabel: appLocalizationsOf(context).close,
              showConfetti: false,
              amountPaid: '\$25.00',
              creditsReceived: '4.5970',
              storageEstimate: '311.1 MB',
              newBalanceCredits: '8.84',
              newBalanceStorage: '598.7 MB',
            ),
            phone: phone,
          ),
          phone: phone,
          dark: dark,
        );
      });
    }
  }
}
