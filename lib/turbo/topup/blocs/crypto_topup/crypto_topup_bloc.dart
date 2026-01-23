import 'dart:async';

import 'package:ardrive/turbo/services/crypto_payment_service.dart';
import 'package:ardrive/turbo/services/crypto_transaction_storage.dart';
import 'package:ardrive/turbo/services/ethereum_wallet_service.dart';
import 'package:ardrive/turbo/services/solana_wallet_service.dart';
import 'package:ardrive/turbo/services/wallet_signer_cache.dart';
import 'package:ardrive/turbo/topup/models/crypto_payment_result.dart';
import 'package:ardrive/turbo/topup/models/crypto_quote.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/pending_transaction.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'crypto_topup_event.dart';
part 'crypto_topup_state.dart';

/// BLoC for managing the cryptocurrency top-up flow.
///
/// This BLoC orchestrates the entire crypto payment flow:
/// 1. Token selection
/// 2. Wallet connection (Ethereum/Solana)
/// 3. AO connect signature (for ARIO via ETH)
/// 4. Amount entry with live quotes
/// 5. Confirmation with network switching
/// 6. Payment processing
/// 7. Success/Error handling
class CryptoTopupBloc extends Bloc<CryptoTopupEvent, CryptoTopupState> {
  final CryptoPaymentService _paymentService;
  final EthereumWalletService _ethereumWalletService;
  final SolanaWalletService _solanaWalletService;
  final WalletSignerCache _signerCache;
  final CryptoTransactionStorage _transactionStorage;
  final String arweaveWalletAddress;

  // Session management
  Timer? _sessionTimer;
  Timer? _quoteTimer;
  Timer? _balanceRefreshTimer;
  static const _sessionTimeout = Duration(minutes: 25);
  static const _quoteExpiration = Duration(minutes: 5);
  static const _balanceRefreshInterval = Duration(minutes: 5);

  // Current flow state
  CryptoToken? _selectedToken;
  CryptoQuote? _currentQuote;
  CryptoQuote? _originalQuote; // For price volatility comparison
  String? _connectedEthAddress;
  int? _connectedChainId;
  String? _connectedSolAddress;
  double _currentAmountUsd = 0;
  bool _isCurrentAmountInTokens = false; // True if amount is in token units
  String? _promoCode;

  // Stream subscriptions
  StreamSubscription<EthereumWalletState?>? _ethWalletSubscription;
  StreamSubscription<SolanaWalletState?>? _solWalletSubscription;
  StreamSubscription<int>? _ethChainSubscription;

  /// Current Turbo balance (in winc) for display on checkout
  final BigInt currentTurboBalance;

  /// Current balance storage estimate (e.g., "5.2 GB")
  final String currentBalanceStorage;

  /// New balance storage estimate (e.g., "7.3 GB")
  final String newBalanceStorage;

  /// Pre-fetched ARIO balance from ArDriveAuth (in ARIO units as string, e.g., "5.0")
  /// Used for ARIO on AO tokens to avoid redundant JS calls
  final String? arioBalance;

  CryptoTopupBloc({
    required CryptoPaymentService paymentService,
    required EthereumWalletService ethereumWalletService,
    required SolanaWalletService solanaWalletService,
    required WalletSignerCache signerCache,
    required CryptoTransactionStorage transactionStorage,
    required this.arweaveWalletAddress,
    BigInt? currentTurboBalance,
    this.currentBalanceStorage = '0 GB',
    this.newBalanceStorage = '0 GB',
    this.arioBalance,
  })  : currentTurboBalance = currentTurboBalance ?? BigInt.zero,
        _paymentService = paymentService,
        _ethereumWalletService = ethereumWalletService,
        _solanaWalletService = solanaWalletService,
        _signerCache = signerCache,
        _transactionStorage = transactionStorage,
        super(const CryptoTopupInitial()) {
    _registerEventHandlers();
    _subscribeToWalletChanges();
  }

  void _registerEventHandlers() {
    on<CryptoTopupStarted>(_onStarted);
    on<CryptoTopupBackPressed>(_onBackPressed);
    on<CryptoTopupTokenSelected>(_onTokenSelected);
    on<CryptoTopupWalletConnectionRequested>(_onWalletConnectionRequested);
    on<CryptoTopupConnectWallet>(_onConnectWallet);
    on<CryptoTopupWalletConnected>(_onWalletConnected);
    on<CryptoTopupWalletConnectionFailed>(_onWalletConnectionFailed);
    on<CryptoTopupWalletDisconnected>(_onWalletDisconnected);
    on<CryptoTopupAccountChanged>(_onAccountChanged);
    on<CryptoTopupAOConnectSignatureRequested>(_onAOConnectSignatureRequested);
    on<CryptoTopupAOConnectSignatureCompleted>(_onAOConnectSignatureCompleted);
    on<CryptoTopupAOConnectSignatureFailed>(_onAOConnectSignatureFailed);
    on<CryptoTopupAmountChanged>(_onAmountChanged);
    on<CryptoTopupInputModeChanged>(_onInputModeChanged);
    on<CryptoTopupPromoCodeSubmitted>(_onPromoCodeSubmitted);
    on<CryptoTopupPromoCodeCleared>(_onPromoCodeCleared);
    on<CryptoTopupQuoteRefreshRequested>(_onQuoteRefreshRequested);
    on<CryptoTopupQuoteRefreshed>(_onQuoteRefreshed);
    on<CryptoTopupProceedToConfirmation>(_onProceedToConfirmation);
    on<CryptoTopupNetworkSwitchRequested>(_onNetworkSwitchRequested);
    on<CryptoTopupNetworkSwitchCompleted>(_onNetworkSwitchCompleted);
    on<CryptoTopupNetworkSwitchFailed>(_onNetworkSwitchFailed);
    on<CryptoTopupNetworkAddRequested>(_onNetworkAddRequested);
    on<CryptoTopupNetworkAddCompleted>(_onNetworkAddCompleted);
    on<CryptoTopupNetworkAddFailed>(_onNetworkAddFailed);
    on<CryptoTopupManualNetworkCheckRequested>(_onManualNetworkCheckRequested);
    on<CryptoTopupPaymentConfirmed>(_onPaymentConfirmed);
    on<CryptoTopupPaymentSucceeded>(_onPaymentSucceeded);
    on<CryptoTopupPaymentFailed>(_onPaymentFailed);
    on<CryptoTopupRetryTransaction>(_onRetryTransaction);
    on<CryptoTopupPriceVolatilityAccepted>(_onPriceVolatilityAccepted);
    on<CryptoTopupPriceVolatilityRejected>(_onPriceVolatilityRejected);
    on<CryptoTopupSessionExpired>(_onSessionExpired);
    on<CryptoTopupConcurrentSessionDetected>(_onConcurrentSessionDetected);
    on<CryptoTopupTakeOverSession>(_onTakeOverSession);
    on<CryptoTopupBalanceFetched>(_onBalanceFetched);
    on<CryptoTopupRefreshBalance>(_onRefreshBalance);

    // UI-friendly event aliases
    on<CryptoTopupSelectToken>(_onSelectToken);
    on<CryptoTopupGoBack>(_onGoBack);
    on<CryptoTopupUpdateAmount>(_onUpdateAmount);
    on<CryptoTopupToggleAmountMode>(_onToggleAmountMode);
    on<CryptoTopupRefreshQuote>(_onRefreshQuote);
    on<CryptoTopupApplyPromoCode>(_onApplyPromoCode);
    on<CryptoTopupRemovePromoCode>(_onRemovePromoCode);
    on<CryptoTopupConfirmPayment>(_onConfirmPayment);
    on<CryptoTopupSwitchNetwork>(_onSwitchNetwork);
    on<CryptoTopupShowManualNetworkSwitch>(_onShowManualNetworkSwitch);
    on<CryptoTopupRetry>(_onRetry);
    on<CryptoTopupClose>(_onClose);
    on<CryptoTopupResumePendingTransaction>(_onResumePendingTransaction);
    on<CryptoTopupCancelAccountChange>(_onCancelAccountChange);
    on<CryptoTopupAcceptAccountChange>(_onAcceptAccountChange);
    on<CryptoTopupRejectNewQuote>(_onRejectNewQuote);
    on<CryptoTopupAcceptNewQuote>(_onAcceptNewQuote);
  }

  /// Calculates storage values based on the current quote.
  /// Returns a record with (currentBalanceStorage, newBalanceStorage).
  ({String currentStorage, String newStorage}) _calculateStorageValues(
      CryptoQuote quote) {
    if (quote.wincAmount > BigInt.zero && quote.estimatedStorageGiB > 0) {
      // Calculate storage per winc based on the quote
      final storagePerWinc =
          quote.estimatedStorageGiB / quote.wincAmount.toDouble();

      // Calculate current balance storage in GiB
      final currentStorageGiB = currentTurboBalance.toDouble() * storagePerWinc;
      final currentStorage = formatStorageWithDynamicUnit(
        currentStorageGiB,
        includeApprox: false,
      );

      // Calculate new balance storage in GiB (current + purchase)
      final newStorageGiB = currentStorageGiB + quote.estimatedStorageGiB;
      final newStorage = formatStorageWithDynamicUnit(
        newStorageGiB,
        includeApprox: false,
      );

      return (currentStorage: currentStorage, newStorage: newStorage);
    }

    return (
      currentStorage: currentBalanceStorage,
      newStorage: newBalanceStorage
    );
  }

  void _subscribeToWalletChanges() {
    // Listen to Ethereum wallet changes
    _ethWalletSubscription = _ethereumWalletService.connectionStream.listen(
      (walletState) {
        if (walletState == null) {
          add(const CryptoTopupWalletDisconnected());
        } else if (_connectedEthAddress != null &&
            _connectedEthAddress!.toLowerCase() !=
                walletState.address.toLowerCase()) {
          add(CryptoTopupAccountChanged(
            newAddress: walletState.address,
            oldAddress: _connectedEthAddress,
          ));
        }
      },
    );

    // Listen to Ethereum chain changes
    _ethChainSubscription = _ethereumWalletService.chainChangeStream.listen(
      (chainId) {
        _connectedChainId = chainId;
        // Re-check network state if we're in confirmation
        if (state is CryptoTopupConfirmation) {
          add(const CryptoTopupManualNetworkCheckRequested());
        }
        // Refresh balance if we're in amount entry (user switched networks)
        if (state is CryptoTopupAmountEntry) {
          add(const CryptoTopupRefreshBalance());
        }
      },
    );

    // Listen to Solana wallet changes
    _solWalletSubscription = _solanaWalletService.connectionStream.listen(
      (walletState) {
        if (walletState == null) {
          add(const CryptoTopupWalletDisconnected());
        } else if (_connectedSolAddress != null &&
            _connectedSolAddress != walletState.address) {
          add(CryptoTopupAccountChanged(
            newAddress: walletState.address,
            oldAddress: _connectedSolAddress,
          ));
        }
      },
    );
  }

  // ============================================
  // Event Handlers
  // ============================================

  Future<void> _onStarted(
    CryptoTopupStarted event,
    Emitter<CryptoTopupState> emit,
  ) async {
    // Start session timer
    _startSessionTimer();

    // Check for concurrent session
    final existingLock = await _transactionStorage.getSessionLock();
    if (existingLock != null && existingLock.isValid) {
      if (existingLock.isDifferentTab(_transactionStorage.tabId)) {
        _cancelAllTimers(); // Cancel session timer we just started
        emit(CryptoTopupConcurrentSessionWarning(
          otherSessionStartedAt: existingLock.timestamp,
          otherTabId: existingLock.tabId,
        ));
        return;
      }
    }

    // Acquire session lock
    await _transactionStorage.acquireSessionLock('token_selection');

    // Check for pending transaction
    PendingCryptoTransaction? pendingTx;
    try {
      pendingTx = await _transactionStorage
          .getPendingTransaction(arweaveWalletAddress);
    } catch (e) {
      logger.w('Error checking pending transactions: $e');
    }

    // Get connected wallet states
    final ethWallet = _ethereumWalletService.connectedWallet;
    final solWallet = _solanaWalletService.connectedWallet;

    _connectedEthAddress = ethWallet?.address;
    _connectedChainId = ethWallet?.chainId;
    _connectedSolAddress = solWallet?.address;

    emit(CryptoTopupTokenSelection(
      ethAddress: _connectedEthAddress,
      ethChainId: _connectedChainId,
      solAddress: _connectedSolAddress,
      pendingTransaction: pendingTx,
      isLoadingBalances: false,
    ));
  }

  Future<void> _onBackPressed(
    CryptoTopupBackPressed event,
    Emitter<CryptoTopupState> emit,
  ) async {
    final currentState = state;

    if (currentState is CryptoTopupWalletConnection ||
        currentState is CryptoTopupWalletNotInstalled) {
      // Go back to token selection
      _selectedToken = null;
      emit(CryptoTopupTokenSelection(
        ethAddress: _connectedEthAddress,
        ethChainId: _connectedChainId,
        solAddress: _connectedSolAddress,
      ));
    } else if (currentState is CryptoTopupAOConnectSignature) {
      // Go back to wallet connection or token selection
      if (_selectedToken?.walletType == WalletType.ethereum) {
        emit(CryptoTopupWalletConnection(
          token: _selectedToken!,
          walletType: WalletType.ethereum,
        ));
      } else {
        emit(CryptoTopupTokenSelection(
          ethAddress: _connectedEthAddress,
          ethChainId: _connectedChainId,
          solAddress: _connectedSolAddress,
        ));
      }
    } else if (currentState is CryptoTopupAmountEntry) {
      // Go back to token selection (clear quote)
      _cancelQuoteTimer();
      _currentQuote = null;
      _originalQuote = null;
      _selectedToken = null;
      emit(CryptoTopupTokenSelection(
        ethAddress: _connectedEthAddress,
        ethChainId: _connectedChainId,
        solAddress: _connectedSolAddress,
      ));
    } else if (currentState is CryptoTopupConfirmation ||
        currentState is CryptoTopupNetworkSwitch) {
      // Go back to amount entry
      if (_selectedToken != null && _currentQuote != null) {
        final balance = await _getTokenBalance(_selectedToken!);
        emit(CryptoTopupAmountEntry(
          token: _selectedToken!,
          walletAddress: _getWalletAddress(_selectedToken!)!,
          balance: balance,
          quote: _currentQuote,
          currentAmount: _currentAmountUsd,
          promoCode: _promoCode,
          promoCodeState:
              _promoCode != null ? PromoCodeState.valid : PromoCodeState.none,
        ));
      }
    } else if (currentState is CryptoTopupPriceVolatilityWarning) {
      // Go back to amount entry with original quote
      _currentQuote = currentState.originalQuote;
      if (_selectedToken != null) {
        final balance = await _getTokenBalance(_selectedToken!);
        emit(CryptoTopupAmountEntry(
          token: _selectedToken!,
          walletAddress: _getWalletAddress(_selectedToken!)!,
          balance: balance,
          quote: _currentQuote,
          currentAmount: _currentAmountUsd,
        ));
      }
    }
  }

  Future<void> _onTokenSelected(
    CryptoTopupTokenSelected event,
    Emitter<CryptoTopupState> emit,
  ) async {
    _selectedToken = event.token;
    final token = event.token;

    // Check if wallet connection is needed
    final walletType = token.walletType;
    final needsWalletConnection = switch (walletType) {
      WalletType.arweave => false, // Already connected
      WalletType.ethereum => _connectedEthAddress == null,
      WalletType.solana => _connectedSolAddress == null,
    };

    if (needsWalletConnection) {
      emit(CryptoTopupWalletConnection(
        token: token,
        walletType: walletType,
      ));
      return;
    }

    // Check if AO connect signature is needed (ARIO via ETH)
    if (token == CryptoToken.arioAOViaEth) {
      if (!_signerCache.hasAOSignature(_connectedEthAddress!)) {
        emit(CryptoTopupAOConnectSignature(
          token: token,
          ethAddress: _connectedEthAddress!,
        ));
        return;
      }
    }

    // Proceed to amount entry
    await _emitAmountEntry(emit, token);
  }

  Future<void> _onWalletConnectionRequested(
    CryptoTopupWalletConnectionRequested event,
    Emitter<CryptoTopupState> emit,
  ) async {
    if (_selectedToken == null) return;

    emit(CryptoTopupWalletConnection(
      token: _selectedToken!,
      walletType: event.walletType,
      isConnecting: true,
    ));

    try {
      if (event.walletType == WalletType.ethereum) {
        final walletState = await _ethereumWalletService.connect(
          provider: event.ethereumProvider,
        );
        add(CryptoTopupWalletConnected(
          address: walletState.address,
          chainId: walletState.chainId,
          walletType: WalletType.ethereum,
        ));
      } else if (event.walletType == WalletType.solana) {
        final walletState = await _solanaWalletService.connect(
          provider: event.solanaProvider,
        );
        add(CryptoTopupWalletConnected(
          address: walletState.address,
          walletType: WalletType.solana,
        ));
      }
    } on EthereumWalletException catch (e) {
      add(CryptoTopupWalletConnectionFailed(
        error: e.userMessage,
        isUserRejected: e.isUserRejected,
        isNotInstalled: e.isNoProvider,
      ));
    } on SolanaWalletException catch (e) {
      add(CryptoTopupWalletConnectionFailed(
        error: e.userMessage,
        isUserRejected: e.isUserRejected,
        isNotInstalled: e.isNoProvider,
      ));
    } catch (e) {
      add(CryptoTopupWalletConnectionFailed(error: e.toString()));
    }
  }

  /// Handle simple connect wallet event from UI
  /// Delegates to the full wallet connection flow using selected token's wallet type
  void _onConnectWallet(
    CryptoTopupConnectWallet event,
    Emitter<CryptoTopupState> emit,
  ) {
    if (_selectedToken == null) return;

    add(CryptoTopupWalletConnectionRequested(
      walletType: _selectedToken!.walletType,
      ethereumProvider: event.ethereumProvider,
      solanaProvider: event.solanaProvider,
    ));
  }

  Future<void> _onWalletConnected(
    CryptoTopupWalletConnected event,
    Emitter<CryptoTopupState> emit,
  ) async {
    if (event.walletType == WalletType.ethereum) {
      _connectedEthAddress = event.address;
      _connectedChainId = event.chainId;
    } else if (event.walletType == WalletType.solana) {
      _connectedSolAddress = event.address;
    }

    if (_selectedToken == null) return;

    // Note: AO connect signature for ARIO via ETH is now deferred to payment time.
    // The signature will be requested lazily by signAndCacheAOConnect() when the
    // user clicks the final "Pay" button, streamlining the checkout flow.

    // For EVM tokens, check if on correct chain and switch if needed
    if (event.walletType == WalletType.ethereum) {
      final requiredChainId = _selectedToken!.chainId;
      if (requiredChainId != null && event.chainId != requiredChainId) {
        // Automatically request network switch
        logger.d('Wrong network: ${event.chainId}, need $requiredChainId. Switching...');
        add(CryptoTopupNetworkSwitchRequested(requiredChainId));
        return;
      }
    }

    // Proceed to amount entry
    await _emitAmountEntry(emit, _selectedToken!);
  }

  void _onWalletConnectionFailed(
    CryptoTopupWalletConnectionFailed event,
    Emitter<CryptoTopupState> emit,
  ) {
    if (_selectedToken == null) return;

    if (event.isNotInstalled) {
      emit(CryptoTopupWalletNotInstalled(
        token: _selectedToken!,
        walletType: _selectedToken!.walletType,
        installUrl: _getWalletInstallUrl(_selectedToken!.walletType),
      ));
    } else {
      emit(CryptoTopupWalletConnection(
        token: _selectedToken!,
        walletType: _selectedToken!.walletType,
        isConnecting: false,
        error: event.error,
        isUserRejected: event.isUserRejected,
      ));
    }
  }

  void _onWalletDisconnected(
    CryptoTopupWalletDisconnected event,
    Emitter<CryptoTopupState> emit,
  ) {
    // Return to token selection with warning
    _selectedToken = null;
    _currentQuote = null;
    _originalQuote = null;
    _connectedEthAddress = null;
    _connectedChainId = null;
    _connectedSolAddress = null;

    emit(const CryptoTopupTokenSelection(
      error: 'Wallet disconnected. Please reconnect to continue.',
    ));
  }

  void _onAccountChanged(
    CryptoTopupAccountChanged event,
    Emitter<CryptoTopupState> emit,
  ) {
    // Clear all payment state and AO signature cache
    _signerCache.clearAll();
    _currentQuote = null;
    _originalQuote = null;
    _selectedToken = null;

    // Update connected address
    if (_connectedEthAddress != null) {
      _connectedEthAddress = event.newAddress;
    } else if (_connectedSolAddress != null) {
      _connectedSolAddress = event.newAddress;
    }

    emit(CryptoTopupAccountChangedWarning(
      oldAddress: event.oldAddress,
      newAddress: event.newAddress,
    ));
  }

  Future<void> _onAOConnectSignatureRequested(
    CryptoTopupAOConnectSignatureRequested event,
    Emitter<CryptoTopupState> emit,
  ) async {
    if (_selectedToken == null || _connectedEthAddress == null) return;

    emit(CryptoTopupAOConnectSignature(
      token: _selectedToken!,
      ethAddress: _connectedEthAddress!,
      isSigningMessage: true,
    ));

    try {
      final signatureData = await _signerCache.signAndCacheAOConnect(
        _ethereumWalletService,
      );
      add(CryptoTopupAOConnectSignatureCompleted(signatureData.publicKey));
    } on EthereumWalletException catch (e) {
      add(CryptoTopupAOConnectSignatureFailed(
        error: e.userMessage,
        isUserRejected: e.isUserRejected,
      ));
    } catch (e) {
      add(CryptoTopupAOConnectSignatureFailed(error: e.toString()));
    }
  }

  Future<void> _onAOConnectSignatureCompleted(
    CryptoTopupAOConnectSignatureCompleted event,
    Emitter<CryptoTopupState> emit,
  ) async {
    if (_selectedToken == null) return;
    await _emitAmountEntry(emit, _selectedToken!);
  }

  void _onAOConnectSignatureFailed(
    CryptoTopupAOConnectSignatureFailed event,
    Emitter<CryptoTopupState> emit,
  ) {
    if (_selectedToken == null || _connectedEthAddress == null) return;

    emit(CryptoTopupAOConnectSignature(
      token: _selectedToken!,
      ethAddress: _connectedEthAddress!,
      isSigningMessage: false,
      error: event.error,
      isUserRejected: event.isUserRejected,
    ));
  }

  Future<void> _onAmountChanged(
    CryptoTopupAmountChanged event,
    Emitter<CryptoTopupState> emit,
  ) async {
    if (_selectedToken == null) return;
    final currentState = state;
    if (currentState is! CryptoTopupAmountEntry) return;

    _currentAmountUsd = event.isUsd ? event.amount : 0;

    // Show loading state
    emit(currentState.copyWith(
      isLoadingQuote: true,
      currentAmount: event.amount,
    ));

    // Fetch quote (debounced in UI layer)
    try {
      final CryptoQuote quote;
      if (event.isUsd) {
        quote = await _paymentService.getQuote(
          token: _selectedToken!,
          usdAmount: event.amount,
          promoCode: _promoCode,
          destinationAddress: arweaveWalletAddress,
        );
      } else {
        quote = await _paymentService.getQuoteByTokenAmount(
          token: _selectedToken!,
          tokenAmount: event.amount,
          promoCode: _promoCode,
          destinationAddress: arweaveWalletAddress,
        );
      }

      _currentQuote = quote;
      _originalQuote ??= quote;

      // Start/restart quote timer
      _startQuoteTimer();

      emit(currentState.copyWith(
        quote: quote,
        isLoadingQuote: false,
        currentAmount: event.amount,
        quoteExpiresAt: quote.expiresAt,
      ));
    } catch (e) {
      logger.e('Error fetching quote: $e');
      emit(currentState.copyWith(
        isLoadingQuote: false,
        error: 'Failed to get quote. Please try again.',
      ));
    }
  }

  void _onInputModeChanged(
    CryptoTopupInputModeChanged event,
    Emitter<CryptoTopupState> emit,
  ) {
    final currentState = state;
    if (currentState is! CryptoTopupAmountEntry) return;

    emit(currentState.copyWith(isUsdMode: event.isUsdMode));
  }

  Future<void> _onPromoCodeSubmitted(
    CryptoTopupPromoCodeSubmitted event,
    Emitter<CryptoTopupState> emit,
  ) async {
    final currentState = state;
    if (currentState is! CryptoTopupAmountEntry) return;
    if (_selectedToken == null) return;

    emit(currentState.copyWith(promoCodeState: PromoCodeState.validating));

    try {
      final validation = await _paymentService.validatePromoCode(
        code: event.code,
        usdAmount: _currentAmountUsd,
        destinationAddress: arweaveWalletAddress,
      );

      if (validation.isValid) {
        _promoCode = event.code;
        emit(currentState.copyWith(
          promoCodeState: PromoCodeState.valid,
          promoCode: event.code,
        ));
        // Refresh quote with promo code
        add(CryptoTopupAmountChanged(
          amount: _currentAmountUsd,
          isUsd: true,
        ));
      } else {
        emit(currentState.copyWith(
          promoCodeState: PromoCodeState.invalid,
          promoError: validation.errorMessage ?? 'Invalid promo code',
        ));
      }
    } catch (e) {
      emit(currentState.copyWith(
        promoCodeState: PromoCodeState.invalid,
        promoError: 'Failed to validate promo code',
      ));
    }
  }

  void _onPromoCodeCleared(
    CryptoTopupPromoCodeCleared event,
    Emitter<CryptoTopupState> emit,
  ) {
    final currentState = state;
    if (currentState is! CryptoTopupAmountEntry) return;

    _promoCode = null;
    emit(currentState.copyWith(
      promoCodeState: PromoCodeState.none,
      promoCode: null,
    ));

    // Refresh quote without promo code
    if (_currentAmountUsd > 0) {
      add(CryptoTopupAmountChanged(
        amount: _currentAmountUsd,
        isUsd: true,
      ));
    }
  }

  Future<void> _onQuoteRefreshRequested(
    CryptoTopupQuoteRefreshRequested event,
    Emitter<CryptoTopupState> emit,
  ) async {
    if (_selectedToken == null || _currentAmountUsd <= 0) return;

    final currentState = state;

    // If we're in the confirmation state, refresh the quote directly
    if (currentState is CryptoTopupConfirmation) {
      // Emit loading state (update the confirmation with a loading indicator)
      emit(currentState.copyWith(isRefreshingQuote: true));

      try {
        final quote = await _paymentService.getQuote(
          token: _selectedToken!,
          usdAmount: _currentAmountUsd,
          promoCode: _promoCode,
          destinationAddress: arweaveWalletAddress,
        );

        _currentQuote = quote;
        _startQuoteTimer();

        // Get token balance for the updated confirmation
        final balance = await _getTokenBalance(_selectedToken!);
        final storageValues = _calculateStorageValues(quote);

        emit(CryptoTopupConfirmation(
          token: currentState.token,
          quote: quote,
          fromAddress: currentState.fromAddress,
          toAddress: currentState.toAddress,
          networkState: currentState.networkState,
          gasEstimateUsd: currentState.gasEstimateUsd,
          promoCode: _promoCode,
          currentChainId: _connectedChainId,
          currentTurboBalance: currentTurboBalance,
          currentBalanceStorage: storageValues.currentStorage,
          newBalanceStorage: storageValues.newStorage,
          tokenBalance: balance.balanceDisplay,
        ));
      } catch (e) {
        logger.e('Error refreshing quote: $e');
        emit(currentState.copyWith(
          isRefreshingQuote: false,
          error: 'Failed to refresh quote',
        ));
      }
      return;
    }

    // Otherwise, use the standard amount changed flow for amount entry state
    add(CryptoTopupAmountChanged(
      amount: _currentAmountUsd,
      isUsd: true,
    ));
  }

  void _onQuoteRefreshed(
    CryptoTopupQuoteRefreshed event,
    Emitter<CryptoTopupState> emit,
  ) {
    // Check for price volatility (>5% change)
    if (_originalQuote != null) {
      final originalCredits = _originalQuote!.creditsDisplay;
      final newCredits = event.newQuote.creditsDisplay;
      final percentChange = originalCredits > 0
          ? ((newCredits - originalCredits) / originalCredits) * 100
          : 0.0;

      if (percentChange.abs() > 5) {
        emit(CryptoTopupPriceVolatilityWarning(
          originalQuote: _originalQuote!,
          newQuote: event.newQuote,
          percentChange: percentChange,
        ));
        return;
      }
    }

    _currentQuote = event.newQuote;
  }

  Future<void> _onProceedToConfirmation(
    CryptoTopupProceedToConfirmation event,
    Emitter<CryptoTopupState> emit,
  ) async {
    if (_selectedToken == null || _currentQuote == null) return;

    final token = _selectedToken!;
    final quote = _currentQuote!;
    final fromAddress = _getWalletAddress(token)!;

    // Get gas estimate for EVM tokens
    double? gasEstimate;
    if (token.requiresGasEstimation) {
      try {
        gasEstimate = await _paymentService.estimateNetworkFee(
          token: token,
          ethereumWallet: _ethereumWalletService,
        );
      } catch (e) {
        logger.w('Failed to estimate gas: $e');
      }
    }

    // The destination address is the Turbo Gateway
    // (actual address is determined by the SDK during payment)
    const toAddress = 'Turbo Gateway';

    // Get token balance from amount entry state if available
    double? tokenBalance;
    final currentState = state;
    if (currentState is CryptoTopupAmountEntry) {
      tokenBalance = currentState.balance.balanceDisplay;
    }

    // Calculate storage values dynamically based on the quote
    final storageValues = _calculateStorageValues(quote);

    emit(CryptoTopupConfirmation(
      token: token,
      quote: quote,
      fromAddress: fromAddress,
      toAddress: toAddress,
      networkState: NetworkState.checking,
      gasEstimateUsd: gasEstimate,
      promoCode: _promoCode,
      currentChainId: _connectedChainId,
      currentTurboBalance: currentTurboBalance,
      currentBalanceStorage: storageValues.currentStorage,
      newBalanceStorage: storageValues.newStorage,
      tokenBalance: tokenBalance,
    ));

    // Check network state
    _checkNetworkState(emit);
  }

  void _checkNetworkState(Emitter<CryptoTopupState> emit) {
    if (_selectedToken == null) return;
    final token = _selectedToken!;
    final currentState = state;

    if (currentState is! CryptoTopupConfirmation) return;

    // Non-EVM tokens don't need network check
    if (token.walletType != WalletType.ethereum) {
      emit(currentState.copyWith(networkState: NetworkState.correct));
      return;
    }

    final requiredChainId = token.chainId;
    if (requiredChainId == null) {
      emit(currentState.copyWith(networkState: NetworkState.correct));
      return;
    }

    final currentChainId = _connectedChainId;
    if (currentChainId == requiredChainId) {
      emit(currentState.copyWith(
        networkState: NetworkState.correct,
        currentChainId: currentChainId,
      ));
    } else {
      emit(currentState.copyWith(
        networkState: NetworkState.needsSwitch,
        currentChainId: currentChainId,
      ));
    }
  }

  Future<void> _onNetworkSwitchRequested(
    CryptoTopupNetworkSwitchRequested event,
    Emitter<CryptoTopupState> emit,
  ) async {
    final currentState = state;

    // Show switching state in UI
    if (currentState is CryptoTopupConfirmation) {
      emit(currentState.copyWith(networkState: NetworkState.switching));
    } else if (currentState is CryptoTopupWalletConnection && _selectedToken != null) {
      // Show switching state on wallet connection screen
      emit(CryptoTopupWalletConnection(
        token: _selectedToken!,
        walletType: _selectedToken!.walletType,
        isConnecting: true, // Show as connecting/switching
        isSwitchingNetwork: true,
      ));
    }

    try {
      await _ethereumWalletService.switchChain(event.targetChainId);
      add(CryptoTopupNetworkSwitchCompleted(event.targetChainId));
    } on EthereumWalletException catch (e) {
      if (e.isChainNotAdded && _selectedToken != null) {
        add(CryptoTopupNetworkAddRequested(_selectedToken!));
      } else {
        add(CryptoTopupNetworkSwitchFailed(e.userMessage));
      }
    } catch (e) {
      add(CryptoTopupNetworkSwitchFailed(e.toString()));
    }
  }

  Future<void> _onNetworkSwitchCompleted(
    CryptoTopupNetworkSwitchCompleted event,
    Emitter<CryptoTopupState> emit,
  ) async {
    _connectedChainId = event.newChainId;
    final currentState = state;

    if (currentState is CryptoTopupConfirmation) {
      emit(currentState.copyWith(
        networkState: NetworkState.correct,
        currentChainId: event.newChainId,
      ));
    } else if (currentState is CryptoTopupNetworkSwitch) {
      // Return to confirmation
      if (_selectedToken != null && _currentQuote != null) {
        final storageValues = _calculateStorageValues(_currentQuote!);
        emit(CryptoTopupConfirmation(
          token: _selectedToken!,
          quote: _currentQuote!,
          fromAddress: _getWalletAddress(_selectedToken!)!,
          toAddress: 'Turbo Gateway',
          networkState: NetworkState.correct,
          promoCode: _promoCode,
          currentChainId: event.newChainId,
          currentTurboBalance: currentTurboBalance,
          currentBalanceStorage: storageValues.currentStorage,
          newBalanceStorage: storageValues.newStorage,
        ));
      }
    } else if (currentState is CryptoTopupWalletConnection && _selectedToken != null) {
      // After wallet connection + network switch, proceed to amount entry
      await _emitAmountEntry(emit, _selectedToken!);
    } else if (currentState is CryptoTopupAmountEntry) {
      // User switched networks from amount entry screen, refresh balance
      add(const CryptoTopupRefreshBalance());
    }
  }

  void _onNetworkSwitchFailed(
    CryptoTopupNetworkSwitchFailed event,
    Emitter<CryptoTopupState> emit,
  ) {
    final currentState = state;

    if (currentState is CryptoTopupConfirmation) {
      emit(currentState.copyWith(
        networkState: NetworkState.switchFailed,
        networkError: event.error,
      ));
    } else if (_selectedToken != null) {
      // Show manual switch instructions
      emit(CryptoTopupNetworkSwitch(
        token: _selectedToken!,
        currentChainId: _connectedChainId ?? 0,
        requiredChainId: _selectedToken!.chainId ?? 0,
        showManualInstructions: true,
        error: event.error,
      ));
    }
  }

  Future<void> _onNetworkAddRequested(
    CryptoTopupNetworkAddRequested event,
    Emitter<CryptoTopupState> emit,
  ) async {
    final currentState = state;

    if (currentState is CryptoTopupConfirmation) {
      emit(currentState.copyWith(networkState: NetworkState.needsAdd));
    }

    try {
      await _ethereumWalletService.addChain(event.token);
      add(const CryptoTopupNetworkAddCompleted());
    } catch (e) {
      add(CryptoTopupNetworkAddFailed(e.toString()));
    }
  }

  void _onNetworkAddCompleted(
    CryptoTopupNetworkAddCompleted event,
    Emitter<CryptoTopupState> emit,
  ) {
    // Try switching again after adding
    if (_selectedToken != null) {
      final chainId = _selectedToken!.chainId;
      if (chainId != null) {
        add(CryptoTopupNetworkSwitchRequested(chainId));
      }
    }
  }

  void _onNetworkAddFailed(
    CryptoTopupNetworkAddFailed event,
    Emitter<CryptoTopupState> emit,
  ) {
    if (_selectedToken != null) {
      emit(CryptoTopupNetworkSwitch(
        token: _selectedToken!,
        currentChainId: _connectedChainId ?? 0,
        requiredChainId: _selectedToken!.chainId ?? 0,
        showManualInstructions: true,
        error: event.error,
      ));
    }
  }

  Future<void> _onManualNetworkCheckRequested(
    CryptoTopupManualNetworkCheckRequested event,
    Emitter<CryptoTopupState> emit,
  ) async {
    // Re-check the current chain
    try {
      final chainId = await _ethereumWalletService.getChainId();
      _connectedChainId = chainId;

      if (_selectedToken != null &&
          chainId == _selectedToken!.chainId &&
          _currentQuote != null) {
        final storageValues = _calculateStorageValues(_currentQuote!);
        emit(CryptoTopupConfirmation(
          token: _selectedToken!,
          quote: _currentQuote!,
          fromAddress: _getWalletAddress(_selectedToken!)!,
          toAddress: 'Turbo Gateway',
          networkState: NetworkState.correct,
          promoCode: _promoCode,
          currentChainId: chainId,
          currentTurboBalance: currentTurboBalance,
          currentBalanceStorage: storageValues.currentStorage,
          newBalanceStorage: storageValues.newStorage,
        ));
      } else {
        // Still wrong network
        final currentState = state;
        if (currentState is CryptoTopupNetworkSwitch) {
          emit(currentState.copyWith(
            error: 'Still connected to wrong network. Please switch manually.',
          ));
        }
      }
    } catch (e) {
      logger.e('Error checking chain: $e');
    }
  }

  Future<void> _onPaymentConfirmed(
    CryptoTopupPaymentConfirmed event,
    Emitter<CryptoTopupState> emit,
  ) async {
    if (_selectedToken == null || _currentQuote == null) return;

    final token = _selectedToken!;
    final quote = _currentQuote!;

    emit(CryptoTopupProcessing(
      token: token,
      estimatedTime: token.estimatedConfirmationTime,
      isSubmitting: true,
    ));

    try {
      final result = await _paymentService.executePayment(
        token: token,
        quote: quote,
        arweaveAddress: arweaveWalletAddress,
        ethereumWallet: token.walletType == WalletType.ethereum
            ? _ethereumWalletService
            : null,
        solanaWallet:
            token.walletType == WalletType.solana ? _solanaWalletService : null,
      );

      if (result.success || result.status == CryptoPaymentStatus.pending) {
        final txId = result.transactionId;

        // Transaction ID should always be present for success/pending results
        if (txId == null) {
          logger.e('Payment returned success/pending but no transaction ID');
          add(const CryptoTopupPaymentFailed(
            error: 'Transaction submitted but no transaction ID received',
            canRetry: true,
          ));
          return;
        }

        // Save pending transaction for recovery
        await _transactionStorage.savePendingTransaction(
          PendingCryptoTransaction.create(
            transactionId: txId,
            token: token,
            tokenAmount: quote.tokenAmount,
            arweaveAddress: arweaveWalletAddress,
            expectedCredits: quote.creditsDisplay,
            usdValue: quote.usdValue,
          ),
        );

        emit(CryptoTopupProcessing(
          txId: txId,
          token: token,
          estimatedTime: token.estimatedConfirmationTime,
          isSubmitting: false,
        ));

        // Wait 3 seconds for blockchain propagation before confirming
        // This matches the turbo-app pattern and ensures the transaction
        // has time to be included in a block before we check status
        logger.d('Waiting 3 seconds for blockchain propagation...');
        await Future.delayed(const Duration(seconds: 3));

        // Emit success - credits should now be available
        add(CryptoTopupPaymentSucceeded(
          txId: txId,
          creditsAdded: BigInt.from((quote.creditsDisplay * 1e12).toInt()),
        ));
      } else {
        add(CryptoTopupPaymentFailed(
          error: result.errorMessage ?? 'Payment failed',
          txId: result.transactionId,
          canRetry: result.canRetry,
          isUserRejected: result.status == CryptoPaymentStatus.userRejected,
        ));
      }
    } catch (e) {
      logger.e('Payment error: $e');
      add(CryptoTopupPaymentFailed(
        error: e.toString(),
        canRetry: true,
      ));
    }
  }

  Future<void> _onPaymentSucceeded(
    CryptoTopupPaymentSucceeded event,
    Emitter<CryptoTopupState> emit,
  ) async {
    // Remove pending transaction
    await _transactionStorage.removePendingTransaction(event.txId);

    // Release session lock
    await _transactionStorage.releaseSessionLock();

    // Calculate new balance from current + credits added
    final newBalance = currentTurboBalance + event.creditsAdded;

    emit(CryptoTopupSuccess(
      txId: event.txId,
      creditsAdded: event.creditsAdded,
      token: _selectedToken!,
      tokenAmountSpent: _currentQuote?.tokenAmountDisplay ?? 0,
      usdValue: _currentQuote?.usdValue,
      newBalance: newBalance,
    ));
  }

  void _onPaymentFailed(
    CryptoTopupPaymentFailed event,
    Emitter<CryptoTopupState> emit,
  ) {
    // Cancel timers when payment fails - user will need to retry or restart
    _cancelQuoteTimer();
    _balanceRefreshTimer?.cancel();

    emit(CryptoTopupError(
      errorType: event.isUserRejected
          ? CryptoTopupErrorType.transactionRejected
          : CryptoTopupErrorType.transactionFailed,
      message: event.error,
      txId: event.txId,
      canRetry: event.canRetry,
      token: _selectedToken,
    ));
  }

  Future<void> _onRetryTransaction(
    CryptoTopupRetryTransaction event,
    Emitter<CryptoTopupState> emit,
  ) async {
    if (_selectedToken == null) return;

    emit(CryptoTopupProcessing(
      txId: event.txId,
      token: _selectedToken!,
      isSubmitting: true,
    ));

    try {
      // Get the pending transaction from storage
      final pendingTx = await _transactionStorage.getPendingTransaction(arweaveWalletAddress);
      if (pendingTx == null || pendingTx.transactionId != event.txId) {
        add(CryptoTopupPaymentFailed(
          error: 'Pending transaction not found',
          txId: event.txId,
          canRetry: false,
        ));
        return;
      }

      final result = await _paymentService.submitPendingTransaction(
        pendingTx,
        ethereumWallet: _selectedToken!.walletType == WalletType.ethereum
            ? _ethereumWalletService
            : null,
        solanaWallet: _selectedToken!.walletType == WalletType.solana
            ? _solanaWalletService
            : null,
      );

      if (result.success) {
        add(CryptoTopupPaymentSucceeded(
          txId: event.txId,
          creditsAdded: BigInt.from(((result.creditsAdded ?? 0) * 1e12).toInt()),
        ));
      } else if (result.status == CryptoPaymentStatus.pending ||
                 result.status == CryptoPaymentStatus.confirmationTimeout) {
        emit(CryptoTopupProcessing(
          txId: event.txId,
          token: _selectedToken!,
          isSubmitting: false,
        ));
      } else {
        add(CryptoTopupPaymentFailed(
          error: result.errorMessage ?? 'Retry failed',
          txId: event.txId,
          canRetry: true,
        ));
      }
    } catch (e) {
      add(CryptoTopupPaymentFailed(
        error: e.toString(),
        txId: event.txId,
        canRetry: true,
      ));
    }
  }

  void _onPriceVolatilityAccepted(
    CryptoTopupPriceVolatilityAccepted event,
    Emitter<CryptoTopupState> emit,
  ) {
    final currentState = state;
    if (currentState is! CryptoTopupPriceVolatilityWarning) return;

    // Update to new quote and continue
    _currentQuote = currentState.newQuote;
    _originalQuote = currentState.newQuote;

    add(const CryptoTopupProceedToConfirmation());
  }

  Future<void> _onPriceVolatilityRejected(
    CryptoTopupPriceVolatilityRejected event,
    Emitter<CryptoTopupState> emit,
  ) async {
    // Return to amount entry with original values
    if (_selectedToken != null) {
      final balance = await _getTokenBalance(_selectedToken!);
      emit(CryptoTopupAmountEntry(
        token: _selectedToken!,
        walletAddress: _getWalletAddress(_selectedToken!)!,
        balance: balance,
        quote: _originalQuote,
        currentAmount: _currentAmountUsd,
      ));
    }
  }

  void _onSessionExpired(
    CryptoTopupSessionExpired event,
    Emitter<CryptoTopupState> emit,
  ) {
    _cancelAllTimers();
    emit(const CryptoTopupSessionTimeout());
  }

  Future<void> _onConcurrentSessionDetected(
    CryptoTopupConcurrentSessionDetected event,
    Emitter<CryptoTopupState> emit,
  ) async {
    _cancelAllTimers(); // Cancel all timers when concurrent session detected
    final lock = await _transactionStorage.getSessionLock();
    if (lock != null) {
      emit(CryptoTopupConcurrentSessionWarning(
        otherSessionStartedAt: lock.timestamp,
        otherTabId: lock.tabId,
      ));
    }
  }

  Future<void> _onTakeOverSession(
    CryptoTopupTakeOverSession event,
    Emitter<CryptoTopupState> emit,
  ) async {
    // Force release old lock and acquire new one
    await _transactionStorage.forceReleaseSessionLock();
    await _transactionStorage.acquireSessionLock('token_selection');

    // Start fresh
    add(const CryptoTopupStarted());
  }

  void _onBalanceFetched(
    CryptoTopupBalanceFetched event,
    Emitter<CryptoTopupState> emit,
  ) {
    final currentState = state;
    if (currentState is CryptoTopupAmountEntry) {
      emit(currentState.copyWith(balance: event.balance));
    }
  }

  Future<void> _onRefreshBalance(
    CryptoTopupRefreshBalance event,
    Emitter<CryptoTopupState> emit,
  ) async {
    if (_selectedToken == null) return;

    final balance = await _getTokenBalance(_selectedToken!);
    add(CryptoTopupBalanceFetched(balance));
  }

  // ============================================
  // Helper Methods
  // ============================================

  Future<void> _emitAmountEntry(
    Emitter<CryptoTopupState> emit,
    CryptoToken token,
  ) async {
    final walletAddress = _getWalletAddress(token);
    if (walletAddress == null) {
      logger.w('Cannot enter amount entry: wallet address is null');
      return;
    }

    final balance = await _getTokenBalance(token);

    // Start balance refresh timer
    _startBalanceRefreshTimer();

    // Emit initial state - use token mode if amount is in tokens
    emit(CryptoTopupAmountEntry(
      token: token,
      walletAddress: walletAddress,
      balance: balance,
      currentAmount: _currentAmountUsd,
      isLoadingQuote: _currentAmountUsd > 0,
      isUsdMode: !_isCurrentAmountInTokens,
    ));

    // If we already have an amount set, fetch the quote
    if (_currentAmountUsd > 0) {
      add(CryptoTopupAmountChanged(
        amount: _currentAmountUsd,
        isUsd: !_isCurrentAmountInTokens,
      ));
    }
  }

  String? _getWalletAddress(CryptoToken token) {
    return switch (token.walletType) {
      WalletType.arweave => arweaveWalletAddress,
      WalletType.ethereum => _connectedEthAddress,
      WalletType.solana => _connectedSolAddress,
    };
  }

  Future<TokenBalance> _getTokenBalance(CryptoToken token) async {
    try {
      // For ARIO on AO, use the pre-fetched balance from ArDriveAuth if available
      // This avoids redundant JS calls and ensures consistency with the profile dropdown
      if (token == CryptoToken.arioAO && arioBalance != null) {
        try {
          // arioBalance is in ARIO units (e.g., "5.0" for 5 ARIO)
          // We need to convert to mARIO (smallest unit) by multiplying by 1e6
          final arioValue = double.parse(arioBalance!);
          final rawBalance = BigInt.from((arioValue * 1e6).round());
          return TokenBalance(
            token: token,
            rawBalance: rawBalance,
            lastUpdated: DateTime.now(),
          );
        } catch (e) {
          logger.w('Failed to parse pre-fetched ARIO balance: $e');
          // Fall through to fetch from service
        }
      }

      return await _paymentService.getTokenBalance(
        token: token,
        ethereumWallet:
            token.walletType == WalletType.ethereum ? _ethereumWalletService : null,
        solanaWallet:
            token.walletType == WalletType.solana ? _solanaWalletService : null,
        arweaveAddress:
            token.walletType == WalletType.arweave ? arweaveWalletAddress : null,
      );
    } catch (e) {
      logger.e('Error fetching balance: $e');
      return TokenBalance.error(token, 'Failed to fetch balance');
    }
  }

  String _getWalletInstallUrl(WalletType walletType) {
    return switch (walletType) {
      WalletType.ethereum => 'https://metamask.io/download/',
      WalletType.solana => 'https://phantom.app/download',
      WalletType.arweave => 'https://arconnect.io/',
    };
  }

  // ============================================
  // Timer Management
  // ============================================

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer(_sessionTimeout, () {
      add(const CryptoTopupSessionExpired());
    });
  }

  void _startQuoteTimer() {
    _cancelQuoteTimer();
    _quoteTimer = Timer(_quoteExpiration, () {
      // Quote expired, request refresh
      add(const CryptoTopupQuoteRefreshRequested());
    });
  }

  void _cancelQuoteTimer() {
    _quoteTimer?.cancel();
    _quoteTimer = null;
  }

  void _startBalanceRefreshTimer() {
    _balanceRefreshTimer?.cancel();
    _balanceRefreshTimer = Timer.periodic(_balanceRefreshInterval, (_) {
      add(const CryptoTopupRefreshBalance());
    });
  }

  void _cancelAllTimers() {
    _sessionTimer?.cancel();
    _quoteTimer?.cancel();
    _balanceRefreshTimer?.cancel();
  }

  // ============================================
  // UI-Friendly Event Handlers
  // ============================================

  void _onSelectToken(
    CryptoTopupSelectToken event,
    Emitter<CryptoTopupState> emit,
  ) {
    add(CryptoTopupTokenSelected(event.token));
  }

  void _onGoBack(
    CryptoTopupGoBack event,
    Emitter<CryptoTopupState> emit,
  ) {
    add(const CryptoTopupBackPressed());
  }

  void _onUpdateAmount(
    CryptoTopupUpdateAmount event,
    Emitter<CryptoTopupState> emit,
  ) {
    // Store the amount for later use when entering amount entry
    // Store raw value - we'll handle USD vs token conversion in the handler
    _currentAmountUsd = event.amount;
    _isCurrentAmountInTokens = !event.isUsd;

    final currentState = state;

    // Only trigger quote fetch if already in amount entry state
    if (currentState is CryptoTopupAmountEntry) {
      add(CryptoTopupAmountChanged(amount: event.amount, isUsd: event.isUsd));
    }
  }

  void _onToggleAmountMode(
    CryptoTopupToggleAmountMode event,
    Emitter<CryptoTopupState> emit,
  ) {
    final currentState = state;
    if (currentState is CryptoTopupAmountEntry) {
      add(CryptoTopupInputModeChanged(!currentState.isUsdMode));
    }
  }

  void _onRefreshQuote(
    CryptoTopupRefreshQuote event,
    Emitter<CryptoTopupState> emit,
  ) {
    add(const CryptoTopupQuoteRefreshRequested());
  }

  void _onApplyPromoCode(
    CryptoTopupApplyPromoCode event,
    Emitter<CryptoTopupState> emit,
  ) {
    add(CryptoTopupPromoCodeSubmitted(event.code));
  }

  void _onRemovePromoCode(
    CryptoTopupRemovePromoCode event,
    Emitter<CryptoTopupState> emit,
  ) {
    add(const CryptoTopupPromoCodeCleared());
  }

  void _onConfirmPayment(
    CryptoTopupConfirmPayment event,
    Emitter<CryptoTopupState> emit,
  ) {
    add(const CryptoTopupPaymentConfirmed());
  }

  void _onSwitchNetwork(
    CryptoTopupSwitchNetwork event,
    Emitter<CryptoTopupState> emit,
  ) {
    add(CryptoTopupNetworkSwitchRequested(event.chainId));
  }

  void _onShowManualNetworkSwitch(
    CryptoTopupShowManualNetworkSwitch event,
    Emitter<CryptoTopupState> emit,
  ) {
    if (_selectedToken != null) {
      emit(CryptoTopupNetworkSwitch(
        token: _selectedToken!,
        currentChainId: _connectedChainId ?? 0,
        requiredChainId: _selectedToken!.chainId ?? 0,
        showManualInstructions: true,
      ));
    }
  }

  void _onRetry(
    CryptoTopupRetry event,
    Emitter<CryptoTopupState> emit,
  ) {
    final currentState = state;
    if (currentState is CryptoTopupError && currentState.txId != null) {
      add(CryptoTopupRetryTransaction(currentState.txId!));
    } else {
      // Restart from token selection
      add(const CryptoTopupStarted());
    }
  }

  Future<void> _onClose(
    CryptoTopupClose event,
    Emitter<CryptoTopupState> emit,
  ) async {
    _cancelAllTimers();
    await _transactionStorage.releaseSessionLock();
  }

  Future<void> _onResumePendingTransaction(
    CryptoTopupResumePendingTransaction event,
    Emitter<CryptoTopupState> emit,
  ) async {
    final pendingTx = await _transactionStorage.getPendingTransaction(arweaveWalletAddress);
    if (pendingTx != null) {
      _selectedToken = pendingTx.token;
      add(CryptoTopupRetryTransaction(pendingTx.transactionId));
    }
  }

  void _onCancelAccountChange(
    CryptoTopupCancelAccountChange event,
    Emitter<CryptoTopupState> emit,
  ) {
    // Disconnect wallet and return to token selection
    _connectedEthAddress = null;
    _connectedChainId = null;
    _connectedSolAddress = null;
    _selectedToken = null;
    _currentQuote = null;
    _originalQuote = null;

    emit(const CryptoTopupTokenSelection());
  }

  void _onAcceptAccountChange(
    CryptoTopupAcceptAccountChange event,
    Emitter<CryptoTopupState> emit,
  ) {
    // Continue with new account - restart from token selection with new address
    emit(CryptoTopupTokenSelection(
      ethAddress: _connectedEthAddress,
      ethChainId: _connectedChainId,
      solAddress: _connectedSolAddress,
    ));
  }

  void _onRejectNewQuote(
    CryptoTopupRejectNewQuote event,
    Emitter<CryptoTopupState> emit,
  ) {
    add(const CryptoTopupPriceVolatilityRejected());
  }

  void _onAcceptNewQuote(
    CryptoTopupAcceptNewQuote event,
    Emitter<CryptoTopupState> emit,
  ) {
    add(const CryptoTopupPriceVolatilityAccepted());
  }

  // ============================================
  // Wallet Detection (public API)
  // ============================================

  /// Detect available Ethereum wallet providers.
  /// Returns detection result with flags for each supported wallet.
  EthereumProviderDetection detectEthereumProviders() {
    return _ethereumWalletService.detectProviders();
  }

  /// Detect available Solana wallet providers.
  /// Returns detection result with flags for each supported wallet.
  SolanaProviderDetection detectSolanaProviders() {
    return _solanaWalletService.detectProviders();
  }

  // ============================================
  // Cleanup
  // ============================================

  @override
  Future<void> close() async {
    _cancelAllTimers();
    await _ethWalletSubscription?.cancel();
    await _solWalletSubscription?.cancel();
    await _ethChainSubscription?.cancel();
    await _transactionStorage.releaseSessionLock();
    return super.close();
  }
}
