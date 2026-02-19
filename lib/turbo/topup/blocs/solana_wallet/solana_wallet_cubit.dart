import 'dart:async';

import 'package:ardrive/turbo/services/solana_wallet_service.dart';
import 'package:ardrive/turbo/services/wallet_signer_cache.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'solana_wallet_state.dart';

/// Cubit for managing Solana wallet connection state.
///
/// This cubit handles:
/// - Wallet detection and connection (Phantom, Solflare)
/// - Balance fetching
/// - Account change events
class SolanaWalletCubit extends Cubit<SolanaWalletCubitState> {
  final SolanaWalletService _walletService;
  final WalletSignerCache _signerCache;

  StreamSubscription<SolanaWalletState?>? _connectionSubscription;

  SolanaWalletCubit({
    required SolanaWalletService walletService,
    required WalletSignerCache signerCache,
  })  : _walletService = walletService,
        _signerCache = signerCache,
        super(const SolanaWalletDisconnected()) {
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
        emit(SolanaWalletConnectedState(
          address: existingConnection.address,
          provider: existingConnection.provider,
        ));
      }
    } catch (e) {
      logger.w('Error checking existing Solana connection: $e');
    }
  }

  /// Connect to a Solana wallet
  Future<void> connect({SolanaWalletProvider? provider}) async {
    emit(SolanaWalletConnecting(provider: provider));

    try {
      final walletState = await _walletService.connect(provider: provider);
      emit(SolanaWalletConnectedState(
        address: walletState.address,
        provider: walletState.provider,
      ));
    } on SolanaWalletException catch (e) {
      emit(SolanaWalletErrorState(
        message: e.userMessage,
        isUserRejected: e.isUserRejected,
        isNotInstalled: e.isNoProvider,
      ));
    } catch (e) {
      emit(SolanaWalletErrorState(message: e.toString()));
    }
  }

  /// Disconnect from wallet
  Future<void> disconnect() async {
    try {
      await _walletService.disconnect();
    } catch (e) {
      logger.w('Error disconnecting Solana wallet: $e');
    }
    _signerCache.clearAllSolana();
    emit(const SolanaWalletDisconnected());
  }

  // ============================================
  // Balance Management
  // ============================================

  /// Fetch SOL balance
  Future<void> fetchBalance() async {
    final currentState = state;
    if (currentState is! SolanaWalletConnectedState) return;

    try {
      final balance = await _walletService.getTokenBalance();
      emit(currentState.copyWith(balance: balance));
    } catch (e) {
      logger.e('Error fetching Solana balance: $e');
      emit(currentState.copyWith(
        balance: TokenBalance.error(CryptoToken.sol, 'Failed to fetch balance'),
      ));
    }
  }

  // ============================================
  // Event Subscriptions
  // ============================================

  void _subscribeToChanges() {
    _connectionSubscription = _walletService.connectionStream.listen(
      (walletState) {
        if (walletState == null) {
          emit(const SolanaWalletDisconnected());
        } else {
          final currentState = state;
          if (currentState is SolanaWalletConnectedState) {
            // Check if account changed
            if (currentState.address != walletState.address) {
              // Clear signer cache for old address
              _signerCache.clearSolanaAddress(currentState.address);
            }
          }
          emit(SolanaWalletConnectedState(
            address: walletState.address,
            provider: walletState.provider,
          ));
        }
      },
    );
  }

  // ============================================
  // Getters
  // ============================================

  /// Whether any Solana wallet is available
  bool get hasWalletAvailable => _walletService.hasWalletAvailable;

  /// Get available wallet providers
  SolanaProviderDetection get availableProviders =>
      _walletService.detectProviders();

  /// Current connected address (if any)
  String? get connectedAddress {
    final currentState = state;
    if (currentState is SolanaWalletConnectedState) {
      return currentState.address;
    }
    return null;
  }

  // ============================================
  // Cleanup
  // ============================================

  @override
  Future<void> close() async {
    await _connectionSubscription?.cancel();
    return super.close();
  }
}
