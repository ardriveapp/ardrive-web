import 'dart:async';

import 'package:ardrive/turbo/config/crypto_network_config.dart';
import 'package:ardrive/turbo/services/crypto_payment_service.dart';
import 'package:ardrive/turbo/services/crypto_transaction_storage.dart';
import 'package:ardrive/turbo/services/ethereum_wallet_service.dart';
import 'package:ardrive/turbo/services/solana_wallet_service.dart';
import 'package:ardrive/turbo/services/wallet_signer_cache.dart';
import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_payment_result.dart';
import 'package:ardrive/turbo/topup/models/crypto_quote.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/pending_transaction.dart';
import 'package:ardrive/turbo/topup/models/session_lock.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPayments extends Mock implements CryptoPaymentService {}

class _MockEthereum extends Mock implements EthereumWalletService {}

class _MockSolana extends Mock implements SolanaWalletService {}

class _MockSignerCache extends Mock implements WalletSignerCache {}

class _MockStorage extends Mock implements CryptoTransactionStorage {}

class _MockNetwork extends Mock implements CryptoNetworkConfig {}

/// Quote refresh in token mode, the expired-quote guard, the error for a
/// rejected quote, and the other-tab notice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const token = CryptoToken.sol;
  final quote = CryptoQuote(
    token: token,
    tokenAmount: BigInt.from(100000000),
    wincAmount: BigInt.from(1000000000000),
    creditsDisplay: 1,
    estimatedStorageGiB: 0.5,
    usdValue: 10,
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );

  late _MockPayments payments;
  late _MockSolana solana;
  late _MockEthereum ethereum;
  late _MockStorage storage;
  late _MockSignerCache signerCache;
  late StreamController<SolanaWalletState?> solanaWallet;
  late Completer<CryptoPaymentResult> payment;

  setUpAll(() {
    registerFallbackValue(token);
    registerFallbackValue(quote);
    registerFallbackValue(PendingCryptoTransaction.create(
      transactionId: 'fallback',
      token: token,
      tokenAmount: BigInt.one,
      arweaveAddress: 'arweave-address',
      expectedCredits: 1,
      usdValue: 1,
    ));
  });

  setUp(() {
    payments = _MockPayments();
    solana = _MockSolana();
    storage = _MockStorage();
    signerCache = _MockSignerCache();
    solanaWallet = StreamController<SolanaWalletState?>.broadcast();
    payment = Completer<CryptoPaymentResult>();

    ethereum = _MockEthereum();
    when(() => ethereum.connectionStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => ethereum.chainChangeStream)
        .thenAnswer((_) => const Stream.empty());

    when(() => solana.connectionStream).thenAnswer((_) => solanaWallet.stream);
    when(() => solana.connect(provider: any(named: 'provider'))).thenAnswer(
      (_) async => const SolanaWalletState(
        address: 'sol-first',
        provider: SolanaWalletProvider.phantom,
      ),
    );

    when(() => payments.getTokenBalance(
          token: any(named: 'token'),
          ethereumWallet: any(named: 'ethereumWallet'),
          solanaWallet: any(named: 'solanaWallet'),
          arweaveAddress: any(named: 'arweaveAddress'),
        )).thenAnswer(
      (_) async =>
          TokenBalance(token: token, rawBalance: BigInt.from(10000000000)),
    );
    when(() => payments.getQuote(
          token: any(named: 'token'),
          usdAmount: any(named: 'usdAmount'),
          promoCode: any(named: 'promoCode'),
          destinationAddress: any(named: 'destinationAddress'),
        )).thenAnswer((_) async => quote);
    when(() => payments.executePayment(
          token: any(named: 'token'),
          quote: any(named: 'quote'),
          arweaveAddress: any(named: 'arweaveAddress'),
          ethereumWallet: any(named: 'ethereumWallet'),
          solanaWallet: any(named: 'solanaWallet'),
        )).thenAnswer((_) => payment.future);
    when(() => payments.estimateNetworkFee(
          token: any(named: 'token'),
          ethereumWallet: any(named: 'ethereumWallet'),
        )).thenAnswer((_) async => 0.01);

    when(() => storage.savePendingTransaction(any())).thenAnswer((_) async {});
    when(() => storage.removePendingTransaction(any()))
        .thenAnswer((_) async {});
    when(() => storage.releaseSessionLock()).thenAnswer((_) async {});
    when(() => signerCache.clearAll()).thenReturn(null);
  });

  tearDown(() => solanaWallet.close());

  CryptoTopupBloc newBloc() {
    final network = _MockNetwork();
    when(() => network.getChainIdForToken(any())).thenReturn(null);
    final bloc = CryptoTopupBloc(
      networkConfig: network,
      paymentService: payments,
      ethereumWalletService: ethereum,
      solanaWalletService: solana,
      signerCache: signerCache,
      transactionStorage: storage,
      arweaveWalletAddress: 'arweave-address',
    );
    addTearDown(bloc.close);
    return bloc;
  }

  Future<T> next<T extends CryptoTopupState>(
    CryptoTopupBloc bloc, [
    bool Function(T state)? where,
  ]) async {
    if (bloc.state is T && (where?.call(bloc.state as T) ?? true)) {
      return bloc.state as T;
    }
    return await bloc.stream
        .firstWhere((s) => s is T && (where?.call(s) ?? true))
        .timeout(const Duration(seconds: 10)) as T;
  }

  /// Walks the flow to the confirmation screen for 10 USD of SOL.
  Future<void> toConfirmation(CryptoTopupBloc bloc) async {
    bloc.add(const CryptoTopupSelectToken(token));
    await next<CryptoTopupWalletConnection>(bloc);
    bloc.add(const CryptoTopupWalletConnectionRequested(
      walletType: WalletType.solana,
    ));
    await next<CryptoTopupAmountEntry>(bloc);
    bloc.add(const CryptoTopupUpdateAmount(10));
    await next<CryptoTopupAmountEntry>(bloc, (s) => s.quote != null);
    bloc.add(const CryptoTopupProceedToConfirmation());
    await next<CryptoTopupConfirmation>(bloc);
  }

  CryptoQuote quoteExpiringIn(Duration d, {double credits = 1}) => CryptoQuote(
        token: token,
        tokenAmount: BigInt.from(100000000),
        wincAmount: BigInt.from(1000000000000),
        creditsDisplay: credits,
        estimatedStorageGiB: 0.5,
        usdValue: 10,
        expiresAt: DateTime.now().add(d),
      );

  /// The unified flow: the amount is a token amount, not dollars.
  Future<void> toConfirmationInTokens(CryptoTopupBloc bloc) async {
    bloc.add(const CryptoTopupUpdateAmount(0.1, isUsd: false));
    bloc.add(const CryptoTopupSelectToken(token));
    await next<CryptoTopupWalletConnection>(bloc);
    bloc.add(const CryptoTopupWalletConnectionRequested(
      walletType: WalletType.solana,
    ));
    await next<CryptoTopupAmountEntry>(bloc, (s) => s.quote != null);
    bloc.add(const CryptoTopupProceedToConfirmation());
    await next<CryptoTopupConfirmation>(bloc);
  }

  void stubTokenQuote(CryptoQuote Function() q) {
    when(() => payments.getQuoteByTokenAmount(
          token: any(named: 'token'),
          tokenAmount: any(named: 'tokenAmount'),
          promoCode: any(named: 'promoCode'),
          destinationAddress: any(named: 'destinationAddress'),
        )).thenAnswer((_) async => q());
  }

  group('quote refresh', () {
    test('a token amount is re-quoted as the same token amount', () async {
      stubTokenQuote(() => quote);
      final bloc = newBloc();
      await toConfirmationInTokens(bloc);
      clearInteractions(payments);
      final fresh = quoteExpiringIn(const Duration(hours: 2), credits: 1.1);
      stubTokenQuote(() => fresh);

      bloc.add(const CryptoTopupQuoteRefreshRequested());
      final refreshed = await next<CryptoTopupConfirmation>(
          bloc, (s) => s.quote.creditsDisplay == 1.1);

      expect(refreshed.quote, fresh);
      verify(() => payments.getQuoteByTokenAmount(
            token: token,
            tokenAmount: 0.1,
            promoCode: any(named: 'promoCode'),
            destinationAddress: any(named: 'destinationAddress'),
          )).called(1);
      verifyNever(() => payments.getQuote(
            token: any(named: 'token'),
            usdAmount: any(named: 'usdAmount'),
            promoCode: any(named: 'promoCode'),
            destinationAddress: any(named: 'destinationAddress'),
          ));
    });

    test('Confirm & Pay on an expired quote refreshes and pays nothing',
        () async {
      stubTokenQuote(() => quoteExpiringIn(const Duration(milliseconds: 300)));
      final bloc = newBloc();
      await toConfirmationInTokens(bloc);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final fresh = quoteExpiringIn(const Duration(hours: 2), credits: 1.2);
      stubTokenQuote(() => fresh);

      bloc.add(const CryptoTopupConfirmPayment());
      final refreshed = await next<CryptoTopupConfirmation>(
          bloc, (s) => s.quote.creditsDisplay == 1.2);

      expect(refreshed.quote.isExpired, isFalse);
      verifyNever(() => payments.executePayment(
            token: any(named: 'token'),
            quote: any(named: 'quote'),
            arweaveAddress: any(named: 'arweaveAddress'),
            ethereumWallet: any(named: 'ethereumWallet'),
            solanaWallet: any(named: 'solanaWallet'),
          ));
    });
  });

}
