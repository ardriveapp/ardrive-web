// Stub implementation for non-web platforms

import 'dart:async';

import 'package:ardrive/turbo/config/crypto_network_config.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';

/// Service for interacting with Solana wallets (Phantom, Solflare).
///
/// Stub implementation for non-web platforms.
class SolanaWalletService {
  SolanaWalletService({required CryptoNetworkConfig networkConfig});

  /// Stream of wallet connection state changes
  Stream<SolanaWalletState?> get connectionStream => Stream.value(null);

  /// Currently connected wallet state
  SolanaWalletState? get connectedWallet => null;

  /// Whether a wallet is currently connected
  bool get isConnected => false;

  /// Dispose resources
  void dispose() {}

  /// Detect available Solana wallet providers
  SolanaProviderDetection detectProviders() {
    return const SolanaProviderDetection();
  }

  /// Check if any Solana wallet is available
  bool get hasWalletAvailable => false;

  /// Connect to a Solana wallet
  Future<SolanaWalletState> connect({SolanaWalletProvider? provider}) async {
    throw UnsupportedError('Solana wallet is only available on web platforms');
  }

  /// Check if already connected
  Future<SolanaWalletState?> checkConnection(
      {SolanaWalletProvider? provider}) async {
    return null;
  }

  /// Disconnect wallet
  Future<void> disconnect() async {}

  /// Get SOL balance for an address
  Future<TokenBalance> getTokenBalance() async {
    return TokenBalance.error(
        CryptoToken.sol, 'Solana wallet is only available on web platforms');
  }

  /// Get the Solana RPC endpoint URL
  String get rpcUrl => '';

  /// Get the Solana wallet provider for transaction signing
  Object? getSolanaProvider() {
    return null;
  }
}

/// Result of Solana provider detection
class SolanaProviderDetection {
  final bool hasAnyProvider;
  final bool hasPhantom;
  final bool hasSolflare;

  const SolanaProviderDetection({
    this.hasAnyProvider = false,
    this.hasPhantom = false,
    this.hasSolflare = false,
  });

  /// Get list of available providers for UI display
  List<SolanaWalletProvider> get availableProviders => [];
}

/// Exception for Solana wallet operations
class SolanaWalletException implements Exception {
  final String message;

  SolanaWalletException(this.message);

  bool get isUserRejected => message == 'USER_REJECTED';
  bool get isNoProvider => message == 'NO_PROVIDER';

  String get userMessage {
    if (isUserRejected) {
      return 'You cancelled the request in your wallet.';
    }
    if (isNoProvider) {
      return 'No Solana wallet detected. Please install Phantom or Solflare.';
    }
    return message;
  }

  @override
  String toString() => 'SolanaWalletException: $message';
}
