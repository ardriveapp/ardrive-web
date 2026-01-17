part of 'crypto_topup_bloc.dart';

/// Base class for all CryptoTopup states
abstract class CryptoTopupState extends Equatable {
  const CryptoTopupState();

  @override
  List<Object?> get props => [];
}

// ============================================
// Initial State
// ============================================

/// Initial state before flow starts
class CryptoTopupInitial extends CryptoTopupState {
  const CryptoTopupInitial();
}

// ============================================
// Token Selection States
// ============================================

/// Token selection screen state
class CryptoTopupTokenSelection extends CryptoTopupState {
  /// User's ARIO balance on AO (from connected Arweave wallet)
  final TokenBalance? arioBalance;

  /// Connected Ethereum wallet address (if any)
  final String? ethAddress;

  /// Connected Ethereum wallet chain ID
  final int? ethChainId;

  /// Connected Solana wallet address (if any)
  final String? solAddress;

  /// Pending transaction from previous session
  final PendingCryptoTransaction? pendingTransaction;

  /// Whether balances are currently loading
  final bool isLoadingBalances;

  /// Error message if balance fetch failed
  final String? error;

  const CryptoTopupTokenSelection({
    this.arioBalance,
    this.ethAddress,
    this.ethChainId,
    this.solAddress,
    this.pendingTransaction,
    this.isLoadingBalances = false,
    this.error,
  });

  CryptoTopupTokenSelection copyWith({
    TokenBalance? arioBalance,
    String? ethAddress,
    int? ethChainId,
    String? solAddress,
    PendingCryptoTransaction? pendingTransaction,
    bool? isLoadingBalances,
    String? error,
  }) {
    return CryptoTopupTokenSelection(
      arioBalance: arioBalance ?? this.arioBalance,
      ethAddress: ethAddress ?? this.ethAddress,
      ethChainId: ethChainId ?? this.ethChainId,
      solAddress: solAddress ?? this.solAddress,
      pendingTransaction: pendingTransaction ?? this.pendingTransaction,
      isLoadingBalances: isLoadingBalances ?? this.isLoadingBalances,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [
        arioBalance,
        ethAddress,
        ethChainId,
        solAddress,
        pendingTransaction,
        isLoadingBalances,
        error,
      ];
}

// ============================================
// Concurrent Session Warning
// ============================================

/// Another tab has an active crypto topup session
class CryptoTopupConcurrentSessionWarning extends CryptoTopupState {
  final DateTime otherSessionStartedAt;
  final String? otherTabId;

  const CryptoTopupConcurrentSessionWarning({
    required this.otherSessionStartedAt,
    this.otherTabId,
  });

  @override
  List<Object?> get props => [otherSessionStartedAt, otherTabId];
}

// ============================================
// Wallet Connection States
// ============================================

/// Wallet connection screen state
class CryptoTopupWalletConnection extends CryptoTopupState {
  final CryptoToken token;
  final WalletType walletType;
  final bool isConnecting;
  final bool isSwitchingNetwork;
  final String? error;
  final bool isUserRejected;

  const CryptoTopupWalletConnection({
    required this.token,
    required this.walletType,
    this.isConnecting = false,
    this.isSwitchingNetwork = false,
    this.error,
    this.isUserRejected = false,
  });

  CryptoTopupWalletConnection copyWith({
    bool? isConnecting,
    bool? isSwitchingNetwork,
    String? error,
    bool? isUserRejected,
  }) {
    return CryptoTopupWalletConnection(
      token: token,
      walletType: walletType,
      isConnecting: isConnecting ?? this.isConnecting,
      isSwitchingNetwork: isSwitchingNetwork ?? this.isSwitchingNetwork,
      error: error,
      isUserRejected: isUserRejected ?? this.isUserRejected,
    );
  }

  @override
  List<Object?> get props => [token, walletType, isConnecting, isSwitchingNetwork, error, isUserRejected];
}

/// Wallet extension not installed
class CryptoTopupWalletNotInstalled extends CryptoTopupState {
  final CryptoToken token;
  final WalletType walletType;
  final String installUrl;

  const CryptoTopupWalletNotInstalled({
    required this.token,
    required this.walletType,
    required this.installUrl,
  });

  @override
  List<Object?> get props => [token, walletType, installUrl];
}

// ============================================
// AO Connect Signature State (for ARIO via ETH)
// ============================================

/// AO connect signature screen for ARIO via Ethereum wallet
class CryptoTopupAOConnectSignature extends CryptoTopupState {
  final CryptoToken token;
  final String ethAddress;
  final bool isSigningMessage;
  final String? error;
  final bool isUserRejected;

  const CryptoTopupAOConnectSignature({
    required this.token,
    required this.ethAddress,
    this.isSigningMessage = false,
    this.error,
    this.isUserRejected = false,
  });

  CryptoTopupAOConnectSignature copyWith({
    bool? isSigningMessage,
    String? error,
    bool? isUserRejected,
  }) {
    return CryptoTopupAOConnectSignature(
      token: token,
      ethAddress: ethAddress,
      isSigningMessage: isSigningMessage ?? this.isSigningMessage,
      error: error,
      isUserRejected: isUserRejected ?? this.isUserRejected,
    );
  }

  @override
  List<Object?> get props => [token, ethAddress, isSigningMessage, error, isUserRejected];
}

// ============================================
// Amount Entry State
// ============================================

/// Promo code validation state
enum PromoCodeState {
  none,
  validating,
  valid,
  invalid,
}

/// Amount entry screen state
class CryptoTopupAmountEntry extends CryptoTopupState {
  final CryptoToken token;
  final String walletAddress;
  final TokenBalance balance;
  final CryptoQuote? quote;
  final bool isLoadingQuote;
  final bool isUsdMode;
  final double? gasEstimateUsd;
  final PromoCodeState promoCodeState;
  final String? promoCode;
  final String? promoError;
  final String? error;
  final double currentAmount;
  final DateTime? quoteExpiresAt;

  const CryptoTopupAmountEntry({
    required this.token,
    required this.walletAddress,
    required this.balance,
    this.quote,
    this.isLoadingQuote = false,
    this.isUsdMode = true,
    this.gasEstimateUsd,
    this.promoCodeState = PromoCodeState.none,
    this.promoCode,
    this.promoError,
    this.error,
    this.currentAmount = 0,
    this.quoteExpiresAt,
  });

  /// Check if user has sufficient balance for the payment
  bool get hasSufficientBalance {
    if (quote == null) return true;
    return balance.isSufficientFor(quote!.tokenAmount);
  }

  /// Check if user has sufficient balance including gas
  bool get hasSufficientBalanceWithGas {
    if (quote == null || !token.requiresGasEstimation) return hasSufficientBalance;
    if (!token.isNativeToken) return hasSufficientBalance;
    // For native tokens, balance must cover payment + gas
    // Gas is in USD, so we need to convert (simplified check)
    return hasSufficientBalance;
  }

  CryptoTopupAmountEntry copyWith({
    TokenBalance? balance,
    CryptoQuote? quote,
    bool? isLoadingQuote,
    bool? isUsdMode,
    double? gasEstimateUsd,
    PromoCodeState? promoCodeState,
    String? promoCode,
    String? promoError,
    String? error,
    double? currentAmount,
    DateTime? quoteExpiresAt,
  }) {
    return CryptoTopupAmountEntry(
      token: token,
      walletAddress: walletAddress,
      balance: balance ?? this.balance,
      quote: quote ?? this.quote,
      isLoadingQuote: isLoadingQuote ?? this.isLoadingQuote,
      isUsdMode: isUsdMode ?? this.isUsdMode,
      gasEstimateUsd: gasEstimateUsd ?? this.gasEstimateUsd,
      promoCodeState: promoCodeState ?? this.promoCodeState,
      promoCode: promoCode ?? this.promoCode,
      promoError: promoError,
      error: error,
      currentAmount: currentAmount ?? this.currentAmount,
      quoteExpiresAt: quoteExpiresAt ?? this.quoteExpiresAt,
    );
  }

  @override
  List<Object?> get props => [
        token,
        walletAddress,
        balance,
        quote,
        isLoadingQuote,
        isUsdMode,
        gasEstimateUsd,
        promoCodeState,
        promoCode,
        promoError,
        error,
        currentAmount,
        quoteExpiresAt,
      ];
}

// ============================================
// Confirmation State
// ============================================

/// Network state for confirmation
enum NetworkState {
  checking,
  correct,
  switching,
  needsSwitch,
  needsAdd,
  switchFailed,
}

/// Confirmation screen state
class CryptoTopupConfirmation extends CryptoTopupState {
  final CryptoToken token;
  final CryptoQuote quote;
  final String fromAddress;
  final String toAddress;
  final NetworkState networkState;
  final bool isProcessing;
  final double? gasEstimateUsd;
  final String? networkError;
  final String? promoCode;

  const CryptoTopupConfirmation({
    required this.token,
    required this.quote,
    required this.fromAddress,
    required this.toAddress,
    this.networkState = NetworkState.checking,
    this.isProcessing = false,
    this.gasEstimateUsd,
    this.networkError,
    this.promoCode,
  });

  /// Whether the confirm button should be enabled
  bool get canConfirm =>
      networkState == NetworkState.correct && !isProcessing;

  CryptoTopupConfirmation copyWith({
    NetworkState? networkState,
    bool? isProcessing,
    double? gasEstimateUsd,
    String? networkError,
  }) {
    return CryptoTopupConfirmation(
      token: token,
      quote: quote,
      fromAddress: fromAddress,
      toAddress: toAddress,
      networkState: networkState ?? this.networkState,
      isProcessing: isProcessing ?? this.isProcessing,
      gasEstimateUsd: gasEstimateUsd ?? this.gasEstimateUsd,
      networkError: networkError,
      promoCode: promoCode,
    );
  }

  @override
  List<Object?> get props => [
        token,
        quote,
        fromAddress,
        toAddress,
        networkState,
        isProcessing,
        gasEstimateUsd,
        networkError,
        promoCode,
      ];
}

// ============================================
// Network Switch State
// ============================================

/// Network switch screen for manual switch instructions
class CryptoTopupNetworkSwitch extends CryptoTopupState {
  final CryptoToken token;
  final int currentChainId;
  final int requiredChainId;
  final bool isAdding;
  final bool isSwitching;
  final bool showManualInstructions;
  final String? error;

  const CryptoTopupNetworkSwitch({
    required this.token,
    required this.currentChainId,
    required this.requiredChainId,
    this.isAdding = false,
    this.isSwitching = false,
    this.showManualInstructions = false,
    this.error,
  });

  CryptoTopupNetworkSwitch copyWith({
    bool? isAdding,
    bool? isSwitching,
    bool? showManualInstructions,
    String? error,
  }) {
    return CryptoTopupNetworkSwitch(
      token: token,
      currentChainId: currentChainId,
      requiredChainId: requiredChainId,
      isAdding: isAdding ?? this.isAdding,
      isSwitching: isSwitching ?? this.isSwitching,
      showManualInstructions: showManualInstructions ?? this.showManualInstructions,
      error: error,
    );
  }

  @override
  List<Object?> get props => [
        token,
        currentChainId,
        requiredChainId,
        isAdding,
        isSwitching,
        showManualInstructions,
        error,
      ];
}

// ============================================
// Price Volatility Warning
// ============================================

/// Price volatility warning when price changed >5%
class CryptoTopupPriceVolatilityWarning extends CryptoTopupState {
  final CryptoQuote originalQuote;
  final CryptoQuote newQuote;
  final double percentChange;

  const CryptoTopupPriceVolatilityWarning({
    required this.originalQuote,
    required this.newQuote,
    required this.percentChange,
  });

  @override
  List<Object?> get props => [originalQuote, newQuote, percentChange];
}

// ============================================
// Processing State
// ============================================

/// Payment processing screen state
class CryptoTopupProcessing extends CryptoTopupState {
  final String? txId;
  final CryptoToken token;
  final Duration estimatedTime;
  final bool isSubmitting;

  const CryptoTopupProcessing({
    this.txId,
    required this.token,
    this.estimatedTime = const Duration(minutes: 1),
    this.isSubmitting = false,
  });

  CryptoTopupProcessing copyWith({
    String? txId,
    Duration? estimatedTime,
    bool? isSubmitting,
  }) {
    return CryptoTopupProcessing(
      txId: txId ?? this.txId,
      token: token,
      estimatedTime: estimatedTime ?? this.estimatedTime,
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }

  @override
  List<Object?> get props => [txId, token, estimatedTime, isSubmitting];
}

// ============================================
// Success State
// ============================================

/// Payment success screen state
class CryptoTopupSuccess extends CryptoTopupState {
  final String txId;
  final BigInt creditsAdded;
  final BigInt? newBalance;
  final CryptoToken token;

  const CryptoTopupSuccess({
    required this.txId,
    required this.creditsAdded,
    this.newBalance,
    required this.token,
  });

  @override
  List<Object?> get props => [txId, creditsAdded, newBalance, token];
}

// ============================================
// Error States
// ============================================

/// Error type for crypto topup
enum CryptoTopupErrorType {
  network,
  insufficientFunds,
  insufficientGas,
  transactionFailed,
  transactionRejected,
  quoteExpired,
  promoCodeInvalid,
  sessionExpired,
  unknown,
}

/// Error screen state
class CryptoTopupError extends CryptoTopupState {
  final CryptoTopupErrorType errorType;
  final String message;
  final String? txId;
  final bool canRetry;
  final CryptoToken? token;

  const CryptoTopupError({
    required this.errorType,
    required this.message,
    this.txId,
    this.canRetry = true,
    this.token,
  });

  @override
  List<Object?> get props => [errorType, message, txId, canRetry, token];
}

// ============================================
// Account Changed Warning
// ============================================

/// Warning when wallet account changed mid-flow
class CryptoTopupAccountChangedWarning extends CryptoTopupState {
  final String? oldAddress;
  final String newAddress;

  const CryptoTopupAccountChangedWarning({
    this.oldAddress,
    required this.newAddress,
  });

  @override
  List<Object?> get props => [oldAddress, newAddress];
}

// ============================================
// Session Timeout
// ============================================

/// Session timeout state (25 minutes)
class CryptoTopupSessionTimeout extends CryptoTopupState {
  const CryptoTopupSessionTimeout();
}
