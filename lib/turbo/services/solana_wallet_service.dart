// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:js_util';

import 'package:ardrive/turbo/config/crypto_network_config.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:http/http.dart' as http;
import 'package:js/js.dart';

/// Service for interacting with Solana wallets (Phantom, Solflare).
///
/// Uses the CryptoWalletBridge JavaScript API for wallet communication.
class SolanaWalletService {
  final CryptoNetworkConfig _networkConfig;

  SolanaWalletState? _connectedWallet;
  final _connectionController = StreamController<SolanaWalletState?>.broadcast();

  bool _listenersRegistered = false;
  SolanaWalletProvider? _activeProvider;

  SolanaWalletService({required CryptoNetworkConfig networkConfig})
      : _networkConfig = networkConfig;

  /// Stream of wallet connection state changes
  Stream<SolanaWalletState?> get connectionStream =>
      _connectionController.stream;

  /// Currently connected wallet state
  SolanaWalletState? get connectedWallet => _connectedWallet;

  /// Whether a wallet is currently connected
  bool get isConnected => _connectedWallet != null;

  /// Dispose resources
  void dispose() {
    _removeListeners();
    _connectionController.close();
  }

  // ============================================
  // Wallet Detection
  // ============================================

  /// Detect available Solana wallet providers
  SolanaProviderDetection detectProviders() {
    try {
      final result = _callBridge('detectSolanaProviders', []);
      return SolanaProviderDetection(
        hasAnyProvider: getProperty(result, 'hasAnyProvider') ?? false,
        hasPhantom: getProperty(result, 'phantom') ?? false,
        hasSolflare: getProperty(result, 'solflare') ?? false,
      );
    } catch (e) {
      logger.w('Error detecting Solana providers: $e');
      return const SolanaProviderDetection();
    }
  }

  /// Check if any Solana wallet is available
  bool get hasWalletAvailable => detectProviders().hasAnyProvider;

  // ============================================
  // Connection
  // ============================================

  /// Connect to a Solana wallet
  ///
  /// [provider] - Wallet provider to connect to
  /// Returns the connected wallet state
  Future<SolanaWalletState> connect({SolanaWalletProvider? provider}) async {
    final providerName = provider != null ? _providerToString(provider) : null;

    try {
      final result =
          await _callBridgeAsync('connectSolanaWallet', [providerName]);

      final address = getProperty(result, 'address') as String;
      final providerType = getProperty(result, 'providerType') as String;

      final detectedProvider = _stringToProvider(providerType);
      _activeProvider = detectedProvider;

      final walletState = SolanaWalletState(
        address: address,
        provider: detectedProvider,
      );

      _connectedWallet = walletState;
      _connectionController.add(walletState);
      _registerListeners();

      logger.d('Connected to Solana wallet: ${walletState.truncatedAddress}');
      return walletState;
    } catch (e) {
      final error = _parseError(e);
      logger.e('Error connecting to Solana wallet: $error');
      throw SolanaWalletException(error);
    }
  }

  /// Check if already connected
  Future<SolanaWalletState?> checkConnection(
      {SolanaWalletProvider? provider}) async {
    final providerName = provider != null ? _providerToString(provider) : null;

    try {
      final isConnected =
          _callBridge('isSolanaConnected', [providerName]) as bool;
      if (!isConnected) return null;

      final publicKey =
          _callBridge('getSolanaPublicKey', [providerName]) as String?;
      if (publicKey == null) return null;

      final detection = detectProviders();
      final detectedProvider = provider ??
          (detection.hasPhantom
              ? SolanaWalletProvider.phantom
              : SolanaWalletProvider.solflare);

      _activeProvider = detectedProvider;

      final walletState = SolanaWalletState(
        address: publicKey,
        provider: detectedProvider,
      );

      _connectedWallet = walletState;
      _connectionController.add(walletState);
      _registerListeners();

      return walletState;
    } catch (e) {
      logger.w('Error checking Solana connection: $e');
      return null;
    }
  }

  /// Disconnect wallet
  Future<void> disconnect() async {
    final providerName =
        _activeProvider != null ? _providerToString(_activeProvider!) : null;

    try {
      await _callBridgeAsync('disconnectSolanaWallet', [providerName]);
    } catch (e) {
      logger.w('Error disconnecting Solana wallet: $e');
    }

    _removeListeners();
    _connectedWallet = null;
    _activeProvider = null;
    _connectionController.add(null);
    logger.d('Disconnected from Solana wallet');
  }

  // ============================================
  // Balance
  // ============================================

  /// Get SOL balance for an address
  ///
  /// Uses Solana JSON-RPC API to fetch the native SOL balance.
  Future<TokenBalance> getTokenBalance() async {
    if (_connectedWallet == null) {
      return TokenBalance.error(CryptoToken.sol, 'Wallet not connected');
    }

    try {
      final address = _connectedWallet!.address;
      final balance = await _getSolBalance(address);

      return TokenBalance(
        token: CryptoToken.sol,
        rawBalance: balance,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      logger.e('Error fetching SOL balance: $e');
      return TokenBalance.error(CryptoToken.sol, _parseError(e));
    }
  }

  /// Fetch SOL balance via Solana JSON-RPC
  Future<BigInt> _getSolBalance(String address) async {
    final rpcUrl = _networkConfig.solanaRpcUrl;

    final requestBody = jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'getBalance',
      'params': [address],
    });

    try {
      final response = await http.post(
        Uri.parse(rpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );

      if (response.statusCode != 200) {
        throw Exception('Solana RPC request failed: ${response.statusCode}');
      }

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;

      if (responseData.containsKey('error')) {
        final error = responseData['error'];
        throw Exception('Solana RPC error: ${error['message'] ?? error}');
      }

      final result = responseData['result'];
      if (result is Map<String, dynamic> && result.containsKey('value')) {
        // Balance is in lamports (1 SOL = 10^9 lamports)
        final lamports = result['value'];
        if (lamports is int) {
          return BigInt.from(lamports);
        } else if (lamports is String) {
          return BigInt.parse(lamports);
        }
      }

      throw Exception('Invalid response format from Solana RPC');
    } catch (e) {
      logger.e('Solana RPC call failed: $e');
      rethrow;
    }
  }

  /// Get the Solana RPC endpoint URL
  String get rpcUrl => _networkConfig.solanaRpcUrl;

  // ============================================
  // Transaction Signing
  // ============================================

  /// Get the Solana wallet provider for transaction signing
  ///
  /// This returns the raw provider object that can be used with the Turbo SDK
  Object? getSolanaProvider() {
    final providerName =
        _activeProvider != null ? _providerToString(_activeProvider!) : null;

    try {
      return _callBridge('getSolanaProvider', [providerName]);
    } catch (e) {
      logger.w('Error getting Solana provider: $e');
      return null;
    }
  }

  // ============================================
  // Event Listeners
  // ============================================

  void _registerListeners() {
    if (_listenersRegistered) return;

    final providerName =
        _activeProvider != null ? _providerToString(_activeProvider!) : null;

    try {
      _callBridge('registerSolanaListeners', [
        providerName,
        allowInterop(_onConnect),
        allowInterop(_onDisconnect),
        allowInterop(_onAccountChange),
      ]);
      _listenersRegistered = true;
    } catch (e) {
      logger.w('Error registering Solana listeners: $e');
    }
  }

  void _removeListeners() {
    if (!_listenersRegistered) return;

    final providerName =
        _activeProvider != null ? _providerToString(_activeProvider!) : null;

    try {
      _callBridge('removeSolanaListeners', [providerName]);
      _listenersRegistered = false;
    } catch (e) {
      logger.w('Error removing Solana listeners: $e');
    }
  }

  void _onConnect(dynamic publicKey) {
    if (publicKey != null && _activeProvider != null) {
      final address = publicKey.toString();
      final walletState = SolanaWalletState(
        address: address,
        provider: _activeProvider!,
      );
      _connectedWallet = walletState;
      _connectionController.add(walletState);
    }
  }

  void _onDisconnect(dynamic error) {
    _connectedWallet = null;
    _connectionController.add(null);
  }

  void _onAccountChange(String? newPublicKey) {
    if (newPublicKey == null) {
      // Account disconnected
      _connectedWallet = null;
      _connectionController.add(null);
    } else if (_connectedWallet != null &&
        _connectedWallet!.address != newPublicKey) {
      // Account changed
      _connectedWallet = _connectedWallet!.copyWith(address: newPublicKey);
      _connectionController.add(_connectedWallet);
    }
  }

  // ============================================
  // Private Helpers
  // ============================================

  dynamic _callBridge(String method, List<dynamic> args) {
    final bridge = getProperty(_globalThis, 'CryptoWalletBridge');
    if (bridge == null) {
      throw SolanaWalletException('CryptoWalletBridge not loaded');
    }
    return callMethod(bridge, method, args);
  }

  Future<dynamic> _callBridgeAsync(String method, List<dynamic> args) async {
    final result = _callBridge(method, args);
    if (result is Future || hasProperty(result, 'then')) {
      return await promiseToFuture(result);
    }
    return result;
  }

  String _parseError(dynamic error) {
    final errorStr = error.toString();
    if (errorStr.contains('USER_REJECTED') ||
        errorStr.contains('rejected') ||
        errorStr.contains('4001')) {
      return 'USER_REJECTED';
    }
    if (errorStr.contains('NO_PROVIDER')) {
      return 'NO_PROVIDER';
    }
    return errorStr;
  }

  String _providerToString(SolanaWalletProvider provider) {
    return switch (provider) {
      SolanaWalletProvider.phantom => 'phantom',
      SolanaWalletProvider.solflare => 'solflare',
    };
  }

  SolanaWalletProvider _stringToProvider(String type) {
    return switch (type) {
      'phantom' => SolanaWalletProvider.phantom,
      'solflare' => SolanaWalletProvider.solflare,
      _ => SolanaWalletProvider.phantom, // Default
    };
  }
}

/// Global reference to JavaScript's globalThis
@JS('globalThis')
external Object get _globalThis;

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
  List<SolanaWalletProvider> get availableProviders {
    final providers = <SolanaWalletProvider>[];
    if (hasPhantom) providers.add(SolanaWalletProvider.phantom);
    if (hasSolflare) providers.add(SolanaWalletProvider.solflare);
    return providers;
  }
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
