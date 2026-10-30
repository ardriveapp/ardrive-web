import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/turbo/config/crypto_network_config.dart';
import 'package:ardrive/turbo/services/crypto_payment_service.dart';
import 'package:ardrive/turbo/services/crypto_transaction_storage.dart';
import 'package:ardrive/turbo/services/ethereum_wallet_service.dart';
import 'package:ardrive/turbo/services/solana_wallet_service.dart';
import 'package:ardrive/turbo/services/wallet_signer_cache.dart';
import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockConfigService extends Mock implements ConfigService {}

class MockAppConfig extends Mock implements AppConfig {}

class MockEthereumWalletService extends Mock implements EthereumWalletService {}

class MockSolanaWalletService extends Mock implements SolanaWalletService {}

class MockCryptoPaymentService extends Mock implements CryptoPaymentService {}

class MockWalletSignerCache extends Mock implements WalletSignerCache {}

class MockCryptoTransactionStorage extends Mock
    implements CryptoTransactionStorage {}

CryptoNetworkConfig networkFor(Flavor flavor) {
  final configService = MockConfigService();
  final config = MockAppConfig();
  when(() => configService.flavor).thenReturn(flavor);
  when(() => configService.config).thenReturn(config);
  when(() => config.arweaveGatewayUrl).thenReturn('https://ar-io.dev');
  when(() => config.defaultTurboUploadUrl).thenReturn('https://upload.example');
  when(() => config.defaultTurboPaymentUrl)
      .thenReturn('https://payment.example');
  return CryptoNetworkConfig.forApp(configService);
}

void main() {
  setUpAll(() {
    registerFallbackValue(CryptoToken.ethBase);
  });

  group('CryptoNetworkConfig.forApp', () {
    test('development pays on the testnets', () {
      final network = networkFor(Flavor.development);

      expect(network.isTestnet, isTrue);
      expect(network.getChainIdForToken(CryptoToken.ethBase), 84532);
      expect(network.getChainIdForToken(CryptoToken.usdcBase), 84532);
      expect(network.getChainIdForToken(CryptoToken.ethL1), 11155111);
      expect(network.turboPaymentUrl, 'https://payment.example');
    });

    for (final flavor in [Flavor.staging, Flavor.production]) {
      test('${flavor.name} pays on mainnet', () {
        final network = networkFor(flavor);

        expect(network.isTestnet, isFalse);
        expect(network.getChainIdForToken(CryptoToken.ethBase), 8453);
        expect(network.getChainIdForToken(CryptoToken.ethL1), 1);
      });
    }
  });

  group('switching the wallet to the token\'s chain', () {
    late MockEthereumWalletService ethereum;
    late MockSolanaWalletService solana;
    late MockCryptoTransactionStorage storage;

    CryptoTopupBloc blocFor(Flavor flavor) => CryptoTopupBloc(
          networkConfig: networkFor(flavor),
          paymentService: MockCryptoPaymentService(),
          ethereumWalletService: ethereum,
          solanaWalletService: solana,
          signerCache: MockWalletSignerCache(),
          transactionStorage: storage,
          arweaveWalletAddress: 'arweave-address',
        );

    setUp(() {
      ethereum = MockEthereumWalletService();
      solana = MockSolanaWalletService();
      storage = MockCryptoTransactionStorage();
      when(() => ethereum.connectionStream)
          .thenAnswer((_) => const Stream.empty());
      when(() => ethereum.chainChangeStream)
          .thenAnswer((_) => const Stream.empty());
      when(() => solana.connectionStream)
          .thenAnswer((_) => const Stream.empty());
      when(() => ethereum.connect(provider: any(named: 'provider')))
          .thenAnswer((_) async => const EthereumWalletState(
                address: '0x6163dC89C5399d9De9E2c8aA0AA506C0bFC3881B',
                chainId: 1,
                provider: EthereumWalletProvider.metamask,
              ));
      when(() => ethereum.addChain(any())).thenAnswer((_) async {});
      when(() => storage.releaseSessionLock()).thenAnswer((_) async {});
    });

    Future<CryptoTopupNetworkSwitch> connectOnWrongChain(
      CryptoTopupBloc bloc,
    ) async {
      bloc.add(const CryptoTopupSelectToken(CryptoToken.ethBase));
      await bloc.stream
          .firstWhere((s) => s is CryptoTopupWalletConnection)
          .timeout(const Duration(seconds: 5));

      final result =
          bloc.stream.firstWhere((s) => s is CryptoTopupNetworkSwitch);
      bloc.add(const CryptoTopupWalletConnectionRequested(
        walletType: WalletType.ethereum,
      ));
      return (await result.timeout(const Duration(seconds: 5)))
          as CryptoTopupNetworkSwitch;
    }

    test(
        'a wallet that adds the chain and still won\'t switch gets the manual '
        'steps, not another add', () async {
      when(() => ethereum.switchChain(any()))
          .thenThrow(EthereumWalletException('CHAIN_NOT_ADDED'));
      final bloc = blocFor(Flavor.development);
      addTearDown(bloc.close);

      final state = await connectOnWrongChain(bloc);

      expect(state.showManualInstructions, isTrue);
      expect(state.requiredChainId, 84532);
      verify(() => ethereum.switchChain(84532)).called(2);
      verify(() => ethereum.addChain(CryptoToken.ethBase)).called(1);
    });

    test(
        'a rejected network add says so in words, not as an exception\'s '
        'text', () async {
      when(() => ethereum.switchChain(any()))
          .thenThrow(EthereumWalletException('CHAIN_NOT_ADDED'));
      when(() => ethereum.addChain(any()))
          .thenThrow(EthereumWalletException('USER_REJECTED'));
      final bloc = blocFor(Flavor.development);
      addTearDown(bloc.close);

      final failed = bloc.stream.firstWhere(
        (s) => s is CryptoTopupNetworkSwitch && s.error != null,
      );
      await connectOnWrongChain(bloc);
      final state = (await failed.timeout(const Duration(seconds: 5)))
          as CryptoTopupNetworkSwitch;

      expect(state.error, 'You cancelled the request in your wallet.');
    });

    test('a network add that fails for another reason gives no exception text',
        () async {
      when(() => ethereum.switchChain(any()))
          .thenThrow(EthereumWalletException('CHAIN_NOT_ADDED'));
      when(() => ethereum.addChain(any())).thenThrow(_Opaque());
      final bloc = blocFor(Flavor.development);
      addTearDown(bloc.close);

      final failed = bloc.stream.firstWhere(
        (s) => s is CryptoTopupNetworkSwitch && s.error != null,
      );
      await connectOnWrongChain(bloc);
      final state = (await failed.timeout(const Duration(seconds: 5)))
          as CryptoTopupNetworkSwitch;

      expect(state.error, isNot(contains('Instance of')));
      expect(state.error, 'Could not add the network. Try again.');
    });

    test('a network add that fails readably keeps its message', () async {
      when(() => ethereum.switchChain(any()))
          .thenThrow(EthereumWalletException('CHAIN_NOT_ADDED'));
      when(() => ethereum.addChain(any()))
          .thenThrow(Exception('the RPC URL was refused'));
      final bloc = blocFor(Flavor.development);
      addTearDown(bloc.close);

      final failed = bloc.stream.firstWhere(
        (s) => s is CryptoTopupNetworkSwitch && s.error != null,
      );
      await connectOnWrongChain(bloc);
      final state = (await failed.timeout(const Duration(seconds: 5)))
          as CryptoTopupNetworkSwitch;

      expect(state.error, 'the RPC URL was refused');
    });

    test('production asks the wallet for Base mainnet', () async {
      when(() => ethereum.switchChain(any()))
          .thenThrow(EthereumWalletException('USER_REJECTED'));
      final bloc = blocFor(Flavor.production);
      addTearDown(bloc.close);

      final state = await connectOnWrongChain(bloc);

      expect(state.requiredChainId, 8453);
      verify(() => ethereum.switchChain(8453)).called(1);
      verifyNever(() => ethereum.addChain(any()));
    });
  });
}

/// An error with no toString of its own: in a release build its text is
/// "Instance of 'minified:Xy'".
class _Opaque implements Exception {}
