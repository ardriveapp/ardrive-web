import 'dart:async';

import 'package:ardrive/turbo/services/ethereum_wallet_service.dart';
import 'package:ardrive/turbo/services/wallet_signer_cache.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'ethereum_wallet_state.dart';

/// Cubit for managing Ethereum wallet connection state.
///
/// This cubit handles:
/// - Wallet detection and connection
/// - Network switching
/// - Balance fetching
/// - Account and chain change events
class EthereumWalletCubit extends Cubit<EthereumWalletCubitState> {
  final EthereumWalletService _walletService;
  final WalletSignerCache _signerCache;

  StreamSubscription<EthereumWalletState?>? _connectionSubscription;
  StreamSubscription<int>? _chainSubscription;

  EthereumWalletCubit({
    required EthereumWalletService walletService,
    required WalletSignerCache signerCache,
  })  : _walletService = walletService,
        _signerCache = signerCache,
        super(const EthereumWalletDisconnected()) {
    _subscribeToChanges();
    _checkExistingConnection();
  }

  // ============================================
  // Connection Management
  // ============================================

  /// Check if a wallet is already connected
  Future<void> _checkExistingConnection() async {
    try {
      final existingConnection = await _walletService.checkConnection();
      if (existingConnection != null) {
        emit(EthereumWalletConnectedState(
          address: existingConnection.address,
          chainId: existingConnection.chainId,
          provider: existingConnection.provider,
        ));
      }
    } catch (e) {
      logger.w('Error checking existing Ethereum connection: $e');
    }
  }

  /// Connect to an Ethereum wallet
  Future<void> connect({EthereumWalletProvider? provider}) async {
    emit(EthereumWalletConnecting(provider: provider));

    try {
      final walletState = await _walletService.connect(provider: provider);
      emit(EthereumWalletConnectedState(
        address: walletState.address,
        chainId: walletState.chainId,
        provider: walletState.provider,
      ));
    } on EthereumWalletException catch (e) {
      emit(EthereumWalletErrorState(
        message: e.userMessage,
        isUserRejected: e.isUserRejected,
        isNotInstalled: e.isNoProvider,
      ));
    } catch (e) {
      emit(EthereumWalletErrorState(message: e.toString()));
    }
  }

  /// Disconnect from wallet
  void disconnect() {
    _walletService.disconnect();
    _signerCache.clearAllEthereum();
    emit(const EthereumWalletDisconnected());
  }

  // ============================================
  // Network Management
  // ============================================

  /// Switch to a different network
  Future<void> switchNetwork(int chainId) async {
    final currentState = state;
    if (currentState is! EthereumWalletConnectedState) return;

    emit(EthereumWalletSwitchingNetwork(
      address: currentState.address,
      currentChainId: currentState.chainId,
      targetChainId: chainId,
      provider: currentState.provider,
    ));

    try {
      await _walletService.switchChain(chainId);
      // State will be updated via the chain change listener
    } on EthereumWalletException catch (e) {
      emit(EthereumWalletErrorState(
        message: e.userMessage,
        isUserRejected: e.isUserRejected,
      ));
    } catch (e) {
      emit(EthereumWalletErrorState(message: e.toString()));
    }
  }

  /// Ensure we're on the correct chain for a token
  Future<bool> ensureCorrectChain(CryptoToken token) async {
    final currentState = state;
    if (currentState is! EthereumWalletConnectedState) return false;

    final requiredChainId = token.chainId;
    if (requiredChainId == null) return true;

    if (currentState.chainId == requiredChainId) return true;

    try {
      await _walletService.ensureCorrectChain(token);
      return true;
    } catch (e) {
      logger.e('Error ensuring correct chain: $e');
      return false;
    }
  }

  // ============================================
  // Balance Management
  // ============================================

  /// Fetch token balance
  Future<void> fetchBalance(CryptoToken token) async {
    final currentState = state;
    if (currentState is! EthereumWalletConnectedState) return;

    try {
      final balance = await _walletService.getTokenBalance(token);
      emit(currentState.copyWith(balance: balance));
    } catch (e) {
      logger.e('Error fetching balance: $e');
      emit(currentState.copyWith(
        balance: TokenBalance.error(token, 'Failed to fetch balance'),
      ));
    }
  }

  // ============================================
  // Event Subscriptions
  // ============================================

  void _subscribeToChanges() {
    // Listen for connection changes
    _connectionSubscription = _walletService.connectionStream.listen(
      (walletState) {
        if (walletState == null) {
          emit(const EthereumWalletDisconnected());
        } else {
          final currentState = state;
          if (currentState is EthereumWalletConnectedState) {
            // Check if account changed
            if (currentState.address.toLowerCase() !=
                walletState.address.toLowerCase()) {
              // Clear signer cache for old address
              _signerCache.clearEthereumAddress(currentState.address);
            }
          }
          emit(EthereumWalletConnectedState(
            address: walletState.address,
            chainId: walletState.chainId,
            provider: walletState.provider,
          ));
        }
      },
    );

    // Listen for chain changes
    _chainSubscription = _walletService.chainChangeStream.listen(
      (chainId) {
        final currentState = state;
        if (currentState is EthereumWalletConnectedState) {
          emit(currentState.copyWith(chainId: chainId));
        } else if (currentState is EthereumWalletSwitchingNetwork) {
          // Network switch completed - preserve the provider from switching state
          emit(EthereumWalletConnectedState(
            address: currentState.address,
            chainId: chainId,
            provider: currentState.provider,
          ));
        }
      },
    );
  }

  // ============================================
  // Getters
  // ============================================

  /// Whether any Ethereum wallet is available
  bool get hasWalletAvailable => _walletService.hasWalletAvailable;

  /// Get available wallet providers
  EthereumProviderDetection get availableProviders =>
      _walletService.detectProviders();

  /// Current connected address (if any)
  String? get connectedAddress {
    final currentState = state;
    if (currentState is EthereumWalletConnectedState) {
      return currentState.address;
    }
    return null;
  }

  /// Current chain ID (if connected)
  int? get currentChainId {
    final currentState = state;
    if (currentState is EthereumWalletConnectedState) {
      return currentState.chainId;
    }
    return null;
  }

  // ============================================
  // Cleanup
  // ============================================

  @override
  Future<void> close() async {
    await _connectionSubscription?.cancel();
    await _chainSubscription?.cancel();
    return super.close();
  }
}
