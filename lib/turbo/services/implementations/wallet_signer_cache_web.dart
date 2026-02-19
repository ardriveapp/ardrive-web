// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:js_util';

import 'package:ardrive/turbo/services/ethereum_wallet_service.dart';
import 'package:ardrive/turbo/services/solana_wallet_service.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:js/js.dart';

/// Unified cache for wallet signers to avoid repeated signature requests.
///
/// This is critical for UX - users should only need to sign ONE message per
/// session, not multiple times. The cache stores:
///
/// 1. Ethereum ethers.js signers (for EVM transactions)
/// 2. Ethereum AO connect signatures (for ARIO on AO via ETH)
/// 3. Solana wallet adapters (for SOL transactions)
///
/// Cache is cleared when the user disconnects or switches accounts.
class WalletSignerCache {
  /// Cache of ethers.js signers by key: `eth_${address}_${chainId}`
  final Map<String, Object> _ethereumSignerCache = {};

  /// Cache of Solana wallet adapters by key: `sol_${address}`
  final Map<String, Object> _solanaSignerCache = {};

  /// Cache of AO connect signatures (derived public keys) by address
  final Map<String, AOSignatureData> _aoSignatureCache = {};

  /// Message used for AO connect signature
  static const aoConnectMessage =
      'Sign this message to connect to Turbo Gateway for ARIO payment';

  // ============================================
  // Ethereum Signer Caching
  // ============================================

  /// Get or create an Ethereum signer for the given wallet state.
  ///
  /// Validates that the wallet is on the requested chain before returning
  /// or caching a signer to prevent wrong-network transaction errors.
  Future<Object> getOrCreateEthereumSigner(
    EthereumWalletService walletService,
    int chainId,
  ) async {
    final wallet = walletService.connectedWallet;
    if (wallet == null) {
      throw SignerCacheException('Ethereum wallet not connected');
    }

    // Verify the wallet is on the correct chain before returning/caching signer
    var currentChainId = await walletService.getChainId();
    if (currentChainId != chainId) {
      logger.w(
        'Wallet on chain $currentChainId but requested $chainId, switching...',
      );
      try {
        await walletService.switchChain(chainId);
      } catch (e) {
        throw SignerCacheException(
          'Failed to switch to chain $chainId: $e',
        );
      }

      // Verify the switch actually worked
      currentChainId = await walletService.getChainId();
      if (currentChainId != chainId) {
        throw SignerCacheException(
          'Chain switch failed: wallet still on chain $currentChainId, expected $chainId',
        );
      }

      // Clear any cached signer for this chain since we just switched
      clearEthereumSignerForChain(wallet.address, chainId);
    }

    final cacheKey = _buildEthereumCacheKey(wallet.address, chainId);

    // Return cached signer if available
    if (_ethereumSignerCache.containsKey(cacheKey)) {
      logger.d('Using cached Ethereum signer for $cacheKey');
      return _ethereumSignerCache[cacheKey]!;
    }

    // Create new signer
    logger.d('Creating new Ethereum signer for $cacheKey');
    final signer = await walletService.getEthersSigner();

    // Cache it
    _ethereumSignerCache[cacheKey] = signer;
    return signer;
  }

  /// Check if we have a cached Ethereum signer
  bool hasEthereumSigner(String address, int chainId) {
    final cacheKey = _buildEthereumCacheKey(address, chainId);
    return _ethereumSignerCache.containsKey(cacheKey);
  }

  // ============================================
  // Solana Signer Caching
  // ============================================

  /// Get or create a Solana wallet adapter for signing
  Future<Object> getOrCreateSolanaSigner(
    SolanaWalletService walletService,
  ) async {
    final wallet = walletService.connectedWallet;
    if (wallet == null) {
      throw SignerCacheException('Solana wallet not connected');
    }

    final cacheKey = _buildSolanaCacheKey(wallet.address);

    // Return cached adapter if available
    if (_solanaSignerCache.containsKey(cacheKey)) {
      logger.d('Using cached Solana signer for $cacheKey');
      return _solanaSignerCache[cacheKey]!;
    }

    // Get the wallet provider/adapter
    logger.d('Creating new Solana signer for $cacheKey');
    final provider = walletService.getSolanaProvider();
    if (provider == null) {
      throw SignerCacheException('Could not get Solana provider');
    }

    // Cache it
    _solanaSignerCache[cacheKey] = provider;
    return provider;
  }

  /// Check if we have a cached Solana signer
  bool hasSolanaSigner(String address) {
    final cacheKey = _buildSolanaCacheKey(address);
    return _solanaSignerCache.containsKey(cacheKey);
  }

  // ============================================
  // AO Connect Signature Caching (for ARIO via ETH)
  // ============================================

  /// Check if we have a cached AO connect signature for an address
  bool hasAOSignature(String address) {
    return _aoSignatureCache.containsKey(address.toLowerCase());
  }

  /// Get the cached AO signature data (signature + derived public key)
  AOSignatureData? getAOSignatureData(String address) {
    return _aoSignatureCache[address.toLowerCase()];
  }

  /// Sign the AO connect message and cache the result
  ///
  /// This is used for ARIO on AO payments from Ethereum wallets.
  /// The signature is used to derive the public key via ecrecover.
  Future<AOSignatureData> signAndCacheAOConnect(
    EthereumWalletService walletService,
  ) async {
    final wallet = walletService.connectedWallet;
    if (wallet == null) {
      throw SignerCacheException('Ethereum wallet not connected');
    }

    final addressKey = wallet.address.toLowerCase();

    // Return cached if available
    if (_aoSignatureCache.containsKey(addressKey)) {
      logger.d('Using cached AO signature for ${wallet.truncatedAddress}');
      return _aoSignatureCache[addressKey]!;
    }

    // Sign the message
    logger.d('Requesting AO connect signature from ${wallet.truncatedAddress}');
    final signature = await walletService.signMessage(aoConnectMessage);

    // Derive public key from signature using ethers.js
    final publicKey = await _derivePublicKey(aoConnectMessage, signature);

    // Cache the result
    final signatureData = AOSignatureData(
      signature: signature,
      publicKey: publicKey,
      address: wallet.address,
    );

    _aoSignatureCache[addressKey] = signatureData;
    logger.d('Cached AO signature for ${wallet.truncatedAddress}');

    return signatureData;
  }

  // ============================================
  // Generic Signer Access
  // ============================================

  /// Get a signer for the given token type
  ///
  /// This is a convenience method that returns the appropriate signer
  /// based on the token's wallet type.
  Future<Object> getSignerForToken(
    CryptoToken token, {
    EthereumWalletService? ethereumWallet,
    SolanaWalletService? solanaWallet,
    int? chainId,
  }) async {
    switch (token.walletType) {
      case WalletType.ethereum:
        if (ethereumWallet == null) {
          throw SignerCacheException('Ethereum wallet service required');
        }
        final effectiveChainId =
            chainId ?? ethereumWallet.connectedWallet?.chainId;
        if (effectiveChainId == null) {
          throw SignerCacheException('Chain ID required for Ethereum signer');
        }
        return getOrCreateEthereumSigner(ethereumWallet, effectiveChainId);

      case WalletType.solana:
        if (solanaWallet == null) {
          throw SignerCacheException('Solana wallet service required');
        }
        return getOrCreateSolanaSigner(solanaWallet);

      case WalletType.arweave:
        // Arweave uses the existing ArConnect wallet, no caching needed here
        // The signer is obtained directly from window.arweaveWallet
        throw SignerCacheException(
          'Arweave signers are managed by ArConnect, not this cache',
        );
    }
  }

  // ============================================
  // Cache Invalidation
  // ============================================

  /// Clear signer cache for a specific Ethereum address and chain ID.
  ///
  /// Call this after switching chains to ensure a fresh signer is created
  /// that's properly connected to the new chain.
  void clearEthereumSignerForChain(String address, int chainId) {
    final cacheKey = _buildEthereumCacheKey(address, chainId);
    if (_ethereumSignerCache.remove(cacheKey) != null) {
      logger.d('Cleared Ethereum signer cache for $cacheKey');
    }
  }

  /// Clear all caches for a specific Ethereum address
  void clearEthereumAddress(String address) {
    final addressLower = address.toLowerCase();

    // Clear Ethereum signer cache entries for this address
    _ethereumSignerCache.removeWhere(
      (key, value) => key.toLowerCase().startsWith('eth_$addressLower'),
    );

    // Clear AO signature cache
    _aoSignatureCache.remove(addressLower);

    logger.d('Cleared Ethereum cache for address: $address');
  }

  /// Clear all caches for a specific Solana address
  void clearSolanaAddress(String address) {
    final cacheKey = _buildSolanaCacheKey(address);
    _solanaSignerCache.remove(cacheKey);

    logger.d('Cleared Solana cache for address: $address');
  }

  /// Clear all Ethereum caches
  void clearAllEthereum() {
    _ethereumSignerCache.clear();
    _aoSignatureCache.clear();
    logger.d('Cleared all Ethereum signer caches');
  }

  /// Clear all Solana caches
  void clearAllSolana() {
    _solanaSignerCache.clear();
    logger.d('Cleared all Solana signer caches');
  }

  /// Clear all cached data
  void clearAll() {
    _ethereumSignerCache.clear();
    _solanaSignerCache.clear();
    _aoSignatureCache.clear();
    logger.d('Cleared all wallet signer caches');
  }

  // ============================================
  // Cache Statistics (for debugging)
  // ============================================

  /// Get cache statistics
  SignerCacheStats get stats => SignerCacheStats(
        ethereumSignerCount: _ethereumSignerCache.length,
        solanaSignerCount: _solanaSignerCache.length,
        aoSignatureCount: _aoSignatureCache.length,
      );

  // ============================================
  // Private Helpers
  // ============================================

  String _buildEthereumCacheKey(String address, int chainId) {
    return 'eth_${address.toLowerCase()}_$chainId';
  }

  String _buildSolanaCacheKey(String address) {
    return 'sol_$address';
  }

  /// Derive public key from signature using ethers.js
  ///
  /// Returns the recovered public key as a hex string with 0x prefix.
  /// Throws [SignerCacheException] on any failure.
  Future<String> _derivePublicKey(String message, String signature) async {
    try {
      // Use ethers.js to recover the public key
      final ethers = getProperty(_globalThis, 'ethers');
      if (ethers == null) {
        throw SignerCacheException('ethers.js not loaded');
      }

      // Hash the message as ethers does for personal_sign
      final messageHash = callMethod(ethers, 'hashMessage', [message]);

      // Get the SigningKey class
      final signingKey = getProperty(ethers, 'SigningKey');
      if (signingKey == null) {
        throw SignerCacheException('ethers.SigningKey not available');
      }

      // Recover the public key - returns hex string with 0x prefix
      final recoveredKey = callMethod(
        signingKey,
        'recoverPublicKey',
        [messageHash, signature],
      );

      // The recovered key is already a hex string with 0x prefix
      final publicKeyHex = recoveredKey.toString();

      // Validate uncompressed public key format:
      // - Must start with '0x04' (0x prefix + 04 uncompressed point indicator)
      // - Must be 132 chars total (0x + 130 hex chars for 65-byte uncompressed key)
      if (!publicKeyHex.startsWith('0x04')) {
        throw SignerCacheException(
          'Invalid public key format: expected uncompressed key starting with 0x04',
        );
      }

      if (publicKeyHex.length != 132) {
        throw SignerCacheException(
          'Invalid public key length: expected 132 characters (0x + 130 hex chars '
          'for 65-byte uncompressed key), got ${publicKeyHex.length}',
        );
      }

      return publicKeyHex;
    } catch (e) {
      logger.e('Error deriving public key: $e');
      if (e is SignerCacheException) {
        rethrow;
      }
      throw SignerCacheException('Failed to derive public key: $e');
    }
  }
}

/// Global reference to JavaScript's globalThis
@JS('globalThis')
external Object get _globalThis;

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
