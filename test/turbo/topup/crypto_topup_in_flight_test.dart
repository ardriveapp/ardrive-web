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

/// A payment is in flight from the moment it is confirmed until it succeeds
/// or fails. Wallet and timer events keep arriving in that window, and none
/// of them may take the payment's screen or its data away: the money moves
/// either way.
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

  final paid = CryptoPaymentResult.success(
    transactionId: 'tx-1',
    token: token,
    creditsAdded: 1,
    newBalance: 1,
  );

  /// Confirms, and returns every state from then on.
  Future<List<CryptoTopupState>> confirm(CryptoTopupBloc bloc) async {
    final seen = <CryptoTopupState>[];
    bloc.stream.listen(seen.add);
    bloc.add(const CryptoTopupConfirmPayment());
    await next<CryptoTopupProcessing>(bloc);
    return seen;
  }

  test('a wallet account change while paying still ends on success', () async {
    final bloc = newBloc();
    await toConfirmation(bloc);
    final seen = await confirm(bloc);

    solanaWallet.add(const SolanaWalletState(
      address: 'sol-second',
      provider: SolanaWalletProvider.phantom,
    ));
    await pumpEventQueue();
    payment.complete(paid);

    final success = await next<CryptoTopupSuccess>(bloc);
    expect(success.txId, 'tx-1');
    expect(success.token, token);
    expect(success.tokenAmountSpent, quote.tokenAmountDisplay);
    expect(seen.whereType<CryptoTopupAccountChangedWarning>(), isEmpty);
    verify(() => storage.removePendingTransaction('tx-1')).called(1);
  });

  test('the wallet disconnecting while paying still ends on success', () async {
    final bloc = newBloc();
    await toConfirmation(bloc);
    final seen = await confirm(bloc);

    solanaWallet.add(null);
    await pumpEventQueue();
    payment.complete(paid);

    final success = await next<CryptoTopupSuccess>(bloc);
    expect(success.token, token);
    expect(seen.whereType<CryptoTopupTokenSelection>(), isEmpty);
  });

  test('the session expiring while paying does not cover the payment',
      () async {
    final bloc = newBloc();
    await toConfirmation(bloc);
    final seen = await confirm(bloc);

    bloc.add(const CryptoTopupSessionExpired());
    await pumpEventQueue();
    expect(bloc.state, isA<CryptoTopupProcessing>());
    payment.complete(paid);

    await next<CryptoTopupSuccess>(bloc);
    expect(seen.whereType<CryptoTopupSessionTimeout>(), isEmpty);
  });

  test('confirming twice pays once', () async {
    final bloc = newBloc();
    await toConfirmation(bloc);

    bloc.add(const CryptoTopupConfirmPayment());
    bloc.add(const CryptoTopupConfirmPayment());
    await next<CryptoTopupProcessing>(bloc);
    await pumpEventQueue();
    payment.complete(paid);
    await next<CryptoTopupSuccess>(bloc);

    verify(() => payments.executePayment(
          token: any(named: 'token'),
          quote: any(named: 'quote'),
          arweaveAddress: any(named: 'arweaveAddress'),
          ethereumWallet: any(named: 'ethereumWallet'),
          solanaWallet: any(named: 'solanaWallet'),
        )).called(1);
  });

  test(
      'a quote refresh finishing after confirm can\'t bring the confirm '
      'screen back', () async {
    final bloc = newBloc();
    await toConfirmation(bloc);
    final refreshed = Completer<CryptoQuote>();
    when(() => payments.getQuote(
          token: any(named: 'token'),
          usdAmount: any(named: 'usdAmount'),
          promoCode: any(named: 'promoCode'),
          destinationAddress: any(named: 'destinationAddress'),
        )).thenAnswer((_) => refreshed.future);

    // The quote timer fires on the confirmation screen, and the person
    // confirms while the new quote is on its way.
    bloc.add(const CryptoTopupQuoteRefreshRequested());
    await pumpEventQueue();
    final seen = await confirm(bloc);
    refreshed.complete(quote);
    await pumpEventQueue();

    expect(bloc.state, isA<CryptoTopupProcessing>());
    bloc.add(const CryptoTopupConfirmPayment());
    await pumpEventQueue();
    payment.complete(paid);
    await next<CryptoTopupSuccess>(bloc);

    expect(seen.whereType<CryptoTopupConfirmation>(), isEmpty);
    verify(() => payments.executePayment(
          token: any(named: 'token'),
          quote: any(named: 'quote'),
          arweaveAddress: any(named: 'arweaveAddress'),
          ethereumWallet: any(named: 'ethereumWallet'),
          solanaWallet: any(named: 'solanaWallet'),
        )).called(1);
  });

  test('a quote refresh finishing while paying leaves the payment alone',
      () async {
    final bloc = newBloc();
    await toConfirmation(bloc);
    final seen = await confirm(bloc);

    // More than 5% off the original quote: outside a payment this warns.
    bloc.add(CryptoTopupQuoteRefreshed(CryptoQuote(
      token: token,
      tokenAmount: quote.tokenAmount,
      wincAmount: quote.wincAmount,
      creditsDisplay: quote.creditsDisplay * 2,
      estimatedStorageGiB: quote.estimatedStorageGiB,
      usdValue: quote.usdValue,
      expiresAt: quote.expiresAt,
    )));
    await pumpEventQueue();
    expect(bloc.state, isA<CryptoTopupProcessing>());
    payment.complete(paid);

    await next<CryptoTopupSuccess>(bloc);
    expect(seen.whereType<CryptoTopupPriceVolatilityWarning>(), isEmpty);
  });

  test('another tab opening a session while paying leaves the payment alone',
      () async {
    when(() => storage.getSessionLock()).thenAnswer((_) async =>
        CryptoTopupSessionLock(
            timestamp: DateTime.now(), tabId: 'other', state: 'confirming'));
    final bloc = newBloc();
    await toConfirmation(bloc);
    final seen = await confirm(bloc);

    bloc.add(const CryptoTopupConcurrentSessionDetected());
    await pumpEventQueue();
    expect(bloc.state, isA<CryptoTopupProcessing>());
    // It returns before touching the timers or the lock, not only before
    // emitting: the emitter alone would hide the warning but still stop them.
    verifyNever(() => storage.getSessionLock());
    payment.complete(paid);

    await next<CryptoTopupSuccess>(bloc);
    expect(seen.whereType<CryptoTopupConcurrentSessionWarning>(), isEmpty);
  });

  test('a wallet account change before paying still warns', () async {
    final bloc = newBloc();
    await toConfirmation(bloc);

    solanaWallet.add(const SolanaWalletState(
      address: 'sol-second',
      provider: SolanaWalletProvider.phantom,
    ));

    final warning = await next<CryptoTopupAccountChangedWarning>(bloc);
    expect(warning.newAddress, 'sol-second');
    verifyNever(() => payments.executePayment(
          token: any(named: 'token'),
          quote: any(named: 'quote'),
          arweaveAddress: any(named: 'arweaveAddress'),
          ethereumWallet: any(named: 'ethereumWallet'),
          solanaWallet: any(named: 'solanaWallet'),
        ));
  });
}
