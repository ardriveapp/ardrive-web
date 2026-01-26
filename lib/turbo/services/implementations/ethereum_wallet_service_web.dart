// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_util';

import 'package:ardrive/turbo/config/crypto_network_config.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:js/js.dart';

/// Service for interacting with Ethereum wallets via browser extensions.
///
/// Supports MetaMask, Coinbase Wallet, Rainbow, and other injected providers.
/// Uses the CryptoWalletBridge JavaScript API for wallet communication.
class EthereumWalletService {
  final CryptoNetworkConfig _networkConfig;
  final Future<double> Function(CryptoToken)? _getTokenPrice;

  EthereumWalletState? _connectedWallet;
  final _connectionController =
      StreamController<EthereumWalletState?>.broadcast();
  final _chainChangeController = StreamController<int>.broadcast();

  bool _listenersRegistered = false;

  EthereumWalletService({
    required CryptoNetworkConfig networkConfig,
    Future<double> Function(CryptoToken)? getTokenPrice,
  })  : _networkConfig = networkConfig,
        _getTokenPrice = getTokenPrice;

  /// Stream of wallet connection state changes
  Stream<EthereumWalletState?> get connectionStream =>
      _connectionController.stream;

  /// Stream of chain ID changes
  Stream<int> get chainChangeStream => _chainChangeController.stream;

  /// Currently connected wallet state
  EthereumWalletState? get connectedWallet => _connectedWallet;

  /// Whether a wallet is currently connected
  bool get isConnected => _connectedWallet != null;

  /// Dispose resources
  void dispose() {
    _removeListeners();
    _connectionController.close();
    _chainChangeController.close();
  }

  // ============================================
  // Wallet Detection
  // ============================================

  /// Detect available Ethereum wallet providers
  EthereumProviderDetection detectProviders() {
    try {
      final result = _callBridge('detectEthereumProviders', []);
      return EthereumProviderDetection(
        hasAnyProvider: getProperty(result, 'hasAnyProvider') ?? false,
        hasMetaMask: getProperty(result, 'metamask') ?? false,
        hasCoinbaseWallet: getProperty(result, 'coinbaseWallet') ?? false,
        hasRainbow: getProperty(result, 'rainbow') ?? false,
        hasBrave: getProperty(result, 'brave') ?? false,
      );
    } catch (e) {
      logger.w('Error detecting Ethereum providers: $e');
      return const EthereumProviderDetection();
    }
  }

  /// Check if any Ethereum wallet is available
  bool get hasWalletAvailable => detectProviders().hasAnyProvider;

  // ============================================
  // Connection
  // ============================================

  /// Connect to an Ethereum wallet
  ///
  /// [provider] - Optional provider preference (metamask, coinbase, etc.)
  /// Returns the connected wallet state
  Future<EthereumWalletState> connect(
      {EthereumWalletProvider? provider}) async {
    try {
      final providerName =
          provider != null ? _providerToString(provider) : null;
      final result =
          await _callBridgeAsync('connectEthereumWallet', [providerName]);

      final address = getProperty(result, 'address') as String;
      final chainId = getProperty(result, 'chainId') as int;
      final providerType = getProperty(result, 'providerType') as String;

      final walletState = EthereumWalletState(
        address: address,
        chainId: chainId,
        provider: _stringToProvider(providerType),
      );

      _connectedWallet = walletState;
      _connectionController.add(walletState);
      _registerListeners();

      logger.d('Connected to Ethereum wallet: ${walletState.truncatedAddress}');
      return walletState;
    } catch (e) {
      final error = _parseError(e);
      logger.e('Error connecting to Ethereum wallet: $error');
      throw EthereumWalletException(error);
    }
  }

  /// Check if already connected (without prompting)
  Future<EthereumWalletState?> checkConnection() async {
    try {
      final accounts =
          await _callBridgeAsync('getEthereumAccounts', []) as List<dynamic>;

      if (accounts.isEmpty) {
        return null;
      }

      final chainId = await _callBridgeAsync('getEthereumChainId', []) as int;

      final walletState = EthereumWalletState(
        address: accounts[0] as String,
        chainId: chainId,
        provider: EthereumWalletProvider.metamask, // Generic
      );

      _connectedWallet = walletState;
      _connectionController.add(walletState);
      _registerListeners();

      return walletState;
    } catch (e) {
      logger.w('Error checking Ethereum connection: $e');
      return null;
    }
  }

  /// Disconnect wallet (clears local state, doesn't revoke permissions)
  void disconnect() {
    _removeListeners();
    _connectedWallet = null;
    _connectionController.add(null);
    logger.d('Disconnected from Ethereum wallet');
  }

  // ============================================
  // Network / Chain Management
  // ============================================

  /// Get current chain ID
  Future<int> getChainId() async {
    try {
      return await _callBridgeAsync('getEthereumChainId', []) as int;
    } catch (e) {
      throw EthereumWalletException(_parseError(e));
    }
  }

  /// Switch to a different chain
  ///
  /// Note: Includes a delay after switching to allow the wallet (e.g., MetaMask)
  /// to fully update its internal state. This prevents issues where signers
  /// are created from a stale provider state.
  Future<void> switchChain(int chainId) async {
    try {
      await _callBridgeAsync('switchEthereumChain', [chainId]);

      // Wait for wallet to fully update its internal state after chain switch.
      // This is crucial - without this delay, creating a signer immediately
      // after switching may use the old chain's context, causing transaction
      // failures like "ERC20: transfer amount exceeds balance" when the
      // transaction is sent to the wrong network.
      // Using 1500ms to match turbo-app's handling (they use 1000-1500ms).
      await Future.delayed(const Duration(milliseconds: 1500));

      // Update local state
      if (_connectedWallet != null) {
        _connectedWallet = _connectedWallet!.copyWith(chainId: chainId);
        _connectionController.add(_connectedWallet);
      }

      logger.d('Switched to chain: $chainId');
    } catch (e) {
      final error = _parseError(e);
      if (error == 'CHAIN_NOT_ADDED') {
        throw EthereumWalletException.chainNotAdded(chainId);
      }
      throw EthereumWalletException(error);
    }
  }

  /// Add a new chain to the wallet
  Future<void> addChain(CryptoToken token) async {
    try {
      final params = _networkConfig.getAddNetworkParams(token);
      await _callBridgeAsync('addEthereumChain', [jsify(params)]);
      logger.d('Added chain for token: ${token.displayName}');
    } catch (e) {
      throw EthereumWalletException(_parseError(e));
    }
  }

  /// Switch to the correct chain for a token, adding it if necessary
  Future<void> ensureCorrectChain(CryptoToken token) async {
    final requiredChainId = _networkConfig.getChainIdForToken(token);
    if (requiredChainId == null) {
      return; // Non-EVM token
    }

    final currentChainId = await getChainId();
    if (currentChainId == requiredChainId) {
      return; // Already on correct chain
    }

    try {
      await switchChain(requiredChainId);
    } on EthereumWalletException catch (e) {
      if (e.isChainNotAdded) {
        // Try to add the chain first
        await addChain(token);
        await switchChain(requiredChainId);
      } else {
        rethrow;
      }
    }
  }

  // ============================================
  // Balance
  // ============================================

  /// Get balance for native token or ERC-20
  Future<BigInt> getBalance({
    required String address,
    String? tokenAddress,
  }) async {
    try {
      final result = await _callBridgeAsync(
        'getEthereumBalance',
        [address, tokenAddress],
      );
      return BigInt.parse(result as String);
    } catch (e) {
      throw EthereumWalletException(_parseError(e));
    }
  }

  /// Get token balance for a specific crypto token
  Future<TokenBalance> getTokenBalance(CryptoToken token) async {
    if (_connectedWallet == null) {
      return TokenBalance.error(token, 'Wallet not connected');
    }

    // Check if on correct chain
    final requiredChainId = _networkConfig.getChainIdForToken(token);
    if (requiredChainId != null &&
        _connectedWallet!.chainId != requiredChainId) {
      return TokenBalance.error(
        token,
        'Please switch to ${_networkConfig.getChainDisplayName(token)}',
        isNetworkError: true,
      );
    }

    try {
      final tokenAddress = _networkConfig.getContractAddressForToken(token);
      final balance = await getBalance(
        address: _connectedWallet!.address,
        tokenAddress: tokenAddress,
      );

      return TokenBalance(
        token: token,
        rawBalance: balance,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      return TokenBalance.error(token, _parseError(e));
    }
  }

  // ============================================
  // Gas Estimation
  // ============================================

  /// Estimate gas for a transaction
  Future<BigInt> estimateGas({
    required String from,
    required String to,
    String? value,
    String? data,
  }) async {
    try {
      final params = {
        'from': from,
        'to': to,
        if (value != null) 'value': value,
        if (data != null) 'data': data,
      };
      final result =
          await _callBridgeAsync('estimateEthereumGas', [jsify(params)]);
      return BigInt.parse(result as String);
    } catch (e) {
      throw EthereumWalletException(_parseError(e));
    }
  }

  /// Get current gas price
  Future<BigInt> getGasPrice() async {
    try {
      final result = await _callBridgeAsync('getEthereumGasPrice', []);
      return BigInt.parse(result as String);
    } catch (e) {
      throw EthereumWalletException(_parseError(e));
    }
  }

  /// Estimate network fee in USD for a token payment
  Future<double> estimateNetworkFeeUsd(CryptoToken token) async {
    if (!token.requiresGasEstimation) return 0;

    try {
      // Get gas price and estimate
      final gasPrice = await getGasPrice();

      // Estimate gas for a typical ERC-20 transfer or native transfer
      final gasLimit = token.isERC20
          ? BigInt.from(65000) // ERC-20 transfer
          : BigInt.from(21000); // Native transfer

      final gasCostWei = gasPrice * gasLimit;
      final gasCostEth = gasCostWei.toDouble() / 1e18;

      // Convert to USD using real-time price if available
      double ethPriceUsd = 3000.0; // Fallback default
      if (_getTokenPrice != null) {
        try {
          // Get ETH price (use ethL1 or ethBase - same underlying asset)
          ethPriceUsd = await _getTokenPrice(CryptoToken.ethL1);
        } catch (e) {
          logger.w('Failed to get ETH price, using fallback: $e');
        }
      }
      return gasCostEth * ethPriceUsd;
    } catch (e) {
      logger.w('Error estimating network fee: $e');
      return 0;
    }
  }

  // ============================================
  // Signing
  // ============================================

  /// Sign a message with the connected wallet
  Future<String> signMessage(String message) async {
    if (_connectedWallet == null) {
      throw EthereumWalletException('Wallet not connected');
    }

    try {
      final result = await _callBridgeAsync(
        'signEthereumMessage',
        [_connectedWallet!.address, message],
      );
      return result as String;
    } catch (e) {
      throw EthereumWalletException(_parseError(e));
    }
  }

  /// Get an ethers.js signer for transaction signing
  Future<Object> getEthersSigner() async {
    try {
      return await _callBridgeAsync('getEthersSigner', []);
    } catch (e) {
      throw EthereumWalletException(_parseError(e));
    }
  }

  // ============================================
  // Event Listeners
  // ============================================

  void _registerListeners() {
    if (_listenersRegistered) return;

    try {
      _callBridge('registerEthereumListeners', [
        allowInterop(_onAccountsChanged),
        allowInterop(_onChainChanged),
        allowInterop(_onDisconnect),
      ]);
      _listenersRegistered = true;
    } catch (e) {
      logger.w('Error registering Ethereum listeners: $e');
    }
  }

  void _removeListeners() {
    if (!_listenersRegistered) return;

    try {
      _callBridge('removeEthereumListeners', []);
      _listenersRegistered = false;
    } catch (e) {
      logger.w('Error removing Ethereum listeners: $e');
    }
  }

  void _onAccountsChanged(List<dynamic> accounts) {
    if (accounts.isEmpty) {
      // Wallet disconnected
      _connectedWallet = null;
      _connectionController.add(null);
    } else {
      // Account changed
      final newAddress = accounts[0] as String;
      if (_connectedWallet != null &&
          _connectedWallet!.address.toLowerCase() != newAddress.toLowerCase()) {
        _connectedWallet = _connectedWallet!.copyWith(address: newAddress);
        _connectionController.add(_connectedWallet);
      }
    }
  }

  void _onChainChanged(int chainId) {
    if (_connectedWallet != null) {
      _connectedWallet = _connectedWallet!.copyWith(chainId: chainId);
      _connectionController.add(_connectedWallet);
    }
    _chainChangeController.add(chainId);
  }

  void _onDisconnect(dynamic error) {
    _connectedWallet = null;
    _connectionController.add(null);
  }

  // ============================================
  // Private Helpers
  // ============================================

  dynamic _callBridge(String method, List<dynamic> args) {
    final bridge = getProperty(globalThis, 'CryptoWalletBridge');
    if (bridge == null) {
      throw EthereumWalletException('CryptoWalletBridge not loaded');
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
    if (errorStr.contains('USER_REJECTED') || errorStr.contains('4001')) {
      return 'USER_REJECTED';
    }
    if (errorStr.contains('NO_PROVIDER')) {
      return 'NO_PROVIDER';
    }
    if (errorStr.contains('CHAIN_NOT_ADDED') || errorStr.contains('4902')) {
      return 'CHAIN_NOT_ADDED';
    }
    return errorStr;
  }

  String _providerToString(EthereumWalletProvider provider) {
    return switch (provider) {
      EthereumWalletProvider.metamask => 'metamask',
      EthereumWalletProvider.coinbaseWallet => 'coinbase',
      EthereumWalletProvider.rainbow => 'rainbow',
      EthereumWalletProvider.walletConnect => 'walletconnect',
    };
  }

  EthereumWalletProvider _stringToProvider(String type) {
    return switch (type) {
      'metamask' => EthereumWalletProvider.metamask,
      'coinbase' => EthereumWalletProvider.coinbaseWallet,
      'rainbow' => EthereumWalletProvider.rainbow,
      _ => EthereumWalletProvider.metamask, // Default
    };
  }
}

/// Global reference to JavaScript's globalThis
@JS('globalThis')
external Object get globalThis;

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
  List<EthereumWalletProvider> get availableProviders {
    final providers = <EthereumWalletProvider>[];
    if (hasMetaMask) providers.add(EthereumWalletProvider.metamask);
    if (hasCoinbaseWallet) providers.add(EthereumWalletProvider.coinbaseWallet);
    if (hasRainbow) providers.add(EthereumWalletProvider.rainbow);
    // Always show WalletConnect as an option for mobile
    providers.add(EthereumWalletProvider.walletConnect);
    return providers;
  }
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
