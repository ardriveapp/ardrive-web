// Stub implementation for non-web platforms

import 'dart:async';

import 'package:ardrive/turbo/config/crypto_network_config.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';

/// Service for interacting with Ethereum wallets via browser extensions.
///
/// Stub implementation for non-web platforms.
class EthereumWalletService {
  EthereumWalletService({
    required CryptoNetworkConfig networkConfig,
    Future<double> Function(CryptoToken)? getTokenPrice,
  });

  /// Stream of wallet connection state changes
  Stream<EthereumWalletState?> get connectionStream => Stream.value(null);

  /// Stream of chain ID changes
  Stream<int> get chainChangeStream => const Stream.empty();

  /// Currently connected wallet state
  EthereumWalletState? get connectedWallet => null;

  /// Whether a wallet is currently connected
  bool get isConnected => false;

  /// Dispose resources
  void dispose() {}

  /// Detect available Ethereum wallet providers
  EthereumProviderDetection detectProviders() {
    return const EthereumProviderDetection();
  }

  /// Check if any Ethereum wallet is available
  bool get hasWalletAvailable => false;

  /// Connect to an Ethereum wallet
  Future<EthereumWalletState> connect(
      {EthereumWalletProvider? provider}) async {
    throw UnsupportedError(
        'Ethereum wallet is only available on web platforms');
  }

  /// Check if already connected (without prompting)
  Future<EthereumWalletState?> checkConnection() async {
    return null;
  }

  /// Disconnect wallet
  void disconnect() {}

  /// Get current chain ID
  Future<int> getChainId() async {
    throw UnsupportedError(
        'Ethereum wallet is only available on web platforms');
  }

  /// Switch to a different chain
  Future<void> switchChain(int chainId) async {
    throw UnsupportedError(
        'Ethereum wallet is only available on web platforms');
  }

  /// Add a new chain to the wallet
  Future<void> addChain(CryptoToken token) async {
    throw UnsupportedError(
        'Ethereum wallet is only available on web platforms');
  }

  /// Switch to the correct chain for a token
  Future<void> ensureCorrectChain(CryptoToken token) async {
    throw UnsupportedError(
        'Ethereum wallet is only available on web platforms');
  }

  /// Get balance for native token or ERC-20
  Future<BigInt> getBalance({
    required String address,
    String? tokenAddress,
  }) async {
    throw UnsupportedError(
        'Ethereum wallet is only available on web platforms');
  }

  /// Get token balance for a specific crypto token
  Future<TokenBalance> getTokenBalance(CryptoToken token) async {
    return TokenBalance.error(
        token, 'Ethereum wallet is only available on web platforms');
  }

  /// Estimate gas for a transaction
  Future<BigInt> estimateGas({
    required String from,
    required String to,
    String? value,
    String? data,
  }) async {
    throw UnsupportedError(
        'Ethereum wallet is only available on web platforms');
  }

  /// Get current gas price
  Future<BigInt> getGasPrice() async {
    throw UnsupportedError(
        'Ethereum wallet is only available on web platforms');
  }

  /// Estimate network fee in USD for a token payment
  Future<double> estimateNetworkFeeUsd(CryptoToken token) async {
    return 0;
  }

  /// Sign a message with the connected wallet
  Future<String> signMessage(String message) async {
    throw UnsupportedError(
        'Ethereum wallet is only available on web platforms');
  }

  /// Get an ethers.js signer for transaction signing
  Future<Object> getEthersSigner() async {
    throw UnsupportedError(
        'Ethereum wallet is only available on web platforms');
  }
}

/// Result of Ethereum provider detection
class EthereumProviderDetection {
  final bool hasAnyProvider;
  final bool hasMetaMask;
  final bool hasCoinbaseWallet;
  final bool hasRainbow;
  final bool hasBrave;

  const EthereumProviderDetection({
    this.hasAnyProvider = false,
    this.hasMetaMask = false,
    this.hasCoinbaseWallet = false,
    this.hasRainbow = false,
    this.hasBrave = false,
  });

  /// Get list of available providers for UI display
  List<EthereumWalletProvider> get availableProviders => [];
}

/// Exception for Ethereum wallet operations
class EthereumWalletException implements Exception {
  final String message;
  final int? chainId;

  EthereumWalletException(this.message, {this.chainId});

  factory EthereumWalletException.chainNotAdded(int chainId) {
    return EthereumWalletException('CHAIN_NOT_ADDED', chainId: chainId);
  }

  bool get isUserRejected => message == 'USER_REJECTED';
  bool get isNoProvider => message == 'NO_PROVIDER';
  bool get isChainNotAdded => message == 'CHAIN_NOT_ADDED';

  String get userMessage {
    if (isUserRejected) {
      return 'You cancelled the request in your wallet.';
    }
    if (isNoProvider) {
      return 'No Ethereum wallet detected. Please install MetaMask or another wallet.';
    }
    if (isChainNotAdded) {
      return 'This network is not added to your wallet.';
    }
    return message;
  }

  @override
  String toString() => 'EthereumWalletException: $message';
}
