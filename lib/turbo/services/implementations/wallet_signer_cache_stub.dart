// Stub implementation for non-web platforms

import 'package:ardrive/turbo/services/ethereum_wallet_service.dart';
import 'package:ardrive/turbo/services/solana_wallet_service.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';

/// Unified cache for wallet signers to avoid repeated signature requests.
///
/// Stub implementation for non-web platforms.
class WalletSignerCache {
  /// Message used for AO connect signature
  static const aoConnectMessage =
      'Sign this message to connect to Turbo Gateway for ARIO payment';

  /// Get or create an Ethereum signer for the given wallet state
  Future<Object> getOrCreateEthereumSigner(
    EthereumWalletService walletService,
    int chainId,
  ) async {
    throw UnsupportedError(
        'Wallet signer cache is only available on web platforms');
  }

  /// Check if we have a cached Ethereum signer
  bool hasEthereumSigner(String address, int chainId) {
    return false;
  }

  /// Get or create a Solana wallet adapter for signing
  Future<Object> getOrCreateSolanaSigner(
    SolanaWalletService walletService,
  ) async {
    throw UnsupportedError(
        'Wallet signer cache is only available on web platforms');
  }

  /// Check if we have a cached Solana signer
  bool hasSolanaSigner(String address) {
    return false;
  }

  /// Check if we have a cached AO connect signature for an address
  bool hasAOSignature(String address) {
    return false;
  }

  /// Get the cached AO signature data (signature + derived public key)
  AOSignatureData? getAOSignatureData(String address) {
    return null;
  }

  /// Sign the AO connect message and cache the result
  Future<AOSignatureData> signAndCacheAOConnect(
    EthereumWalletService walletService,
  ) async {
    throw UnsupportedError(
        'Wallet signer cache is only available on web platforms');
  }

  /// Get a signer for the given token type
  Future<Object> getSignerForToken(
    CryptoToken token, {
    EthereumWalletService? ethereumWallet,
    SolanaWalletService? solanaWallet,
    int? chainId,
  }) async {
    throw UnsupportedError(
        'Wallet signer cache is only available on web platforms');
  }

  /// Clear Ethereum signer cache for a specific chain
  void clearEthereumSignerForChain(String address, int chainId) {}

  /// Clear all caches for a specific Ethereum address
  void clearEthereumAddress(String address) {}

  /// Clear all caches for a specific Solana address
  void clearSolanaAddress(String address) {}

  /// Clear all Ethereum caches
  void clearAllEthereum() {}

  /// Clear all Solana caches
  void clearAllSolana() {}

  /// Clear all cached data
  void clearAll() {}

  /// Get cache statistics
  SignerCacheStats get stats => SignerCacheStats(
        ethereumSignerCount: 0,
        solanaSignerCount: 0,
        aoSignatureCount: 0,
      );
}

/// Cached AO signature data for ARIO on AO via Ethereum wallet
class AOSignatureData {
  /// The raw signature from personal_sign
  final String signature;

  /// The derived public key (recovered via ecrecover)
  final String publicKey;

  /// The Ethereum address that signed
  final String address;

  AOSignatureData({
    required this.signature,
    required this.publicKey,
    required this.address,
  });

  @override
  String toString() =>
      'AOSignatureData{address: $address, hasSignature: ${signature.isNotEmpty}}';
}

/// Statistics about cached signers
class SignerCacheStats {
  final int ethereumSignerCount;
  final int solanaSignerCount;
  final int aoSignatureCount;

  SignerCacheStats({
    required this.ethereumSignerCount,
    required this.solanaSignerCount,
    required this.aoSignatureCount,
  });

  int get totalCount =>
      ethereumSignerCount + solanaSignerCount + aoSignatureCount;

  @override
  String toString() =>
      'SignerCacheStats{ethereum: $ethereumSignerCount, solana: $solanaSignerCount, ao: $aoSignatureCount}';
}

/// Exception for signer cache operations
class SignerCacheException implements Exception {
  final String message;

  SignerCacheException(this.message);

  @override
  String toString() => 'SignerCacheException: $message';
}
