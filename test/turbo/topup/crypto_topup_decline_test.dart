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
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive/turbo/topup/models/wallet_decline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPayments extends Mock implements CryptoPaymentService {}

class _MockEthereum extends Mock implements EthereumWalletService {}

class _MockSolana extends Mock implements SolanaWalletService {}

class _MockSignerCache extends Mock implements WalletSignerCache {}

class _MockStorage extends Mock implements CryptoTransactionStorage {}

class _MockNetwork extends Mock implements CryptoNetworkConfig {}

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
        )).thenAnswer((_) async => throw StateError('set per test'));
    when(() => payments.estimateNetworkFee(
          token: any(named: 'token'),
          ethereumWallet: any(named: 'ethereumWallet'),
        )).thenAnswer((_) async => 0.01);

    when(() => storage.savePendingTransaction(any())).thenAnswer((_) async {});
    when(() => storage.removePendingTransaction(any()))
        .thenAnswer((_) async {});
    when(() => storage.releaseSessionLock()).thenAnswer((_) async {});
    when(() => storage.updateSessionLockState(any()))
        .thenAnswer((_) async => true);
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

  void paymentThrows(Object error) {
    when(() => payments.executePayment(
          token: any(named: 'token'),
          quote: any(named: 'quote'),
          arweaveAddress: any(named: 'arweaveAddress'),
          ethereumWallet: any(named: 'ethereumWallet'),
          solanaWallet: any(named: 'solanaWallet'),
        )).thenAnswer((_) async => throw error);
  }

  void paymentReturns(CryptoPaymentResult result) {
    when(() => payments.executePayment(
          token: any(named: 'token'),
          quote: any(named: 'quote'),
          arweaveAddress: any(named: 'arweaveAddress'),
          ethereumWallet: any(named: 'ethereumWallet'),
          solanaWallet: any(named: 'solanaWallet'),
        )).thenAnswer((_) async => result);
  }

  Future<CryptoTopupError> confirmToError(CryptoTopupBloc bloc) async {
    await toConfirmation(bloc);
    bloc.add(const CryptoTopupConfirmPayment());
    return next<CryptoTopupError>(bloc);
  }

  group('a payment declined in the wallet', () {
    test('thrown as a raw wallet error is "no payment made", not a failure',
        () async {
      paymentThrows(Exception(
          'User rejected the request. (code 4001, eth_sendTransaction)'));
      final error = await confirmToError(newBloc());

      expect(error.errorType, CryptoTopupErrorType.transactionRejected);
      expect(error.txId, isNull);
    });

    test('reported by the payment service as a decline is the same', () async {
      paymentReturns(CryptoPaymentResult.failure(
        status: CryptoPaymentStatus.userRejected,
        token: token,
      ));
      final error = await confirmToError(newBloc());

      expect(error.errorType, CryptoTopupErrorType.transactionRejected);
    });
  });

  group('a payment that may have been sent keeps the cautious outcome', () {
    test('a network failure with no readable cause is a transaction failure',
        () async {
      paymentThrows(Exception('Failed to fetch'));
      final error = await confirmToError(newBloc());

      expect(error.errorType, CryptoTopupErrorType.transactionFailed);
    });

    test('a failure that carries a transaction id stays a failure with it',
        () async {
      paymentReturns(CryptoPaymentResult.failure(
        status: CryptoPaymentStatus.failed,
        transactionId: 'tx-9',
        errorMessage: 'The transaction failed on the blockchain.',
        token: token,
      ));
      final error = await confirmToError(newBloc());

      expect(error.errorType, CryptoTopupErrorType.transactionFailed);
      expect(error.txId, 'tx-9');
    });
  });

  test('Try again after a decline connects the wallet again', () async {
    paymentThrows(Exception('User rejected the request. (code 4001)'));
    final bloc = newBloc();
    await confirmToError(bloc);

    bloc.add(const CryptoTopupRetry());
    await next<CryptoTopupTokenSelection>(bloc);
    clearInteractions(solana);

    // The connect screen of a flow that opened with its token chosen.
    bloc.add(const CryptoTopupConnectWallet());
    final entry = await next<CryptoTopupAmountEntry>(bloc);

    verify(() => solana.connect(provider: any(named: 'provider'))).called(1);
    expect(entry.token, token);
    expect(entry.currentAmount, 10);
  });

  group('isWalletDecline', () {
    test('knows the ways wallets report a decline', () {
      expect(isWalletDecline(Exception('User rejected the request.')), isTrue);
      expect(
          isWalletDecline(Exception(
              'user rejected action (action="sendTransaction", code=ACTION_REJECTED)')),
          isTrue);
      expect(isWalletDecline(Exception('{code: 4001}')), isTrue);
      expect(
          isWalletDecline(Exception('{"code": 4001, "message": "x"}')), isTrue);
      expect(isWalletDecline(Exception('code=4001')), isTrue);
      // As ethers really reports a MetaMask decline: the request payload
      // carries the hex calldata of the transaction that was never sent.
      final calldata = '0x${'7475726f43726564697444657374696e6174696f6e' * 4}';
      expect(
          isWalletDecline(Exception(
              'Error: user rejected action (action="sendTransaction", reason="rejected", info={ "error": { "code": 4001, "message": "ethers-user-denied: User rejected the request." }, "payload": { "id": 6, "jsonrpc": "2.0", "method": "eth_sendTransaction", "params": [ { "data": "$calldata" } ] } }, code=ACTION_REJECTED, version=6.13.4)')),
          isTrue);
      expect(isWalletDecline(Exception('User denied transaction signature')),
          isTrue);
    });

    test('does not take a failure for a decline', () {
      expect(isWalletDecline(Exception('Failed to fetch')), isFalse);
      expect(isWalletDecline(Exception('execution reverted')), isFalse);
      expect(isWalletDecline(Exception('insufficient funds for gas')), isFalse);
      expect(isWalletDecline(Exception('tx 0xab14001cd failed')), isFalse);
      // 4001 that is not an error code: an ethers request id after a send,
      // an amount, a port, a status.
      expect(
          isWalletDecline(Exception(
              'missing response for request (value=[ ], info={ "payload": { "id": 4001, "method": "eth_getTransactionByHash" } }, code=BAD_DATA)')),
          isFalse);
      expect(isWalletDecline(Exception('amount 0.4001 too low')), isFalse);
      expect(
          isWalletDecline(
              Exception('connect to https://rpc.example:4001/v1 failed')),
          isFalse);
      expect(isWalletDecline(Exception('status 4001')), isFalse);
      // The SDK's failure after a send, even with decline words in it.
      expect(
          isWalletDecline(Exception(
              "Failed to submit fund transaction! Save this Transaction ID and try again with 'turbo.submitFundTransaction(id)': 0xabc user rejected")),
          isFalse);
    });
  });
}
