part of 'crypto_topup_bloc.dart';

/// Base class for all CryptoTopup events
abstract class CryptoTopupEvent extends Equatable {
  const CryptoTopupEvent();

  @override
  List<Object?> get props => [];
}

// ============================================
// Flow Control Events
// ============================================

/// Initialize the crypto topup flow
class CryptoTopupStarted extends CryptoTopupEvent {
  const CryptoTopupStarted();
}

/// Navigate back to previous step
class CryptoTopupBackPressed extends CryptoTopupEvent {
  const CryptoTopupBackPressed();
}

// ============================================
// Token Selection Events
// ============================================

/// User selected a token to pay with
class CryptoTopupTokenSelected extends CryptoTopupEvent {
  final CryptoToken token;

  const CryptoTopupTokenSelected(this.token);

  @override
  List<Object?> get props => [token];
}

// ============================================
// Wallet Connection Events
// ============================================

/// Request wallet connection for a specific wallet type
class CryptoTopupWalletConnectionRequested extends CryptoTopupEvent {
  final WalletType walletType;
  final EthereumWalletProvider? ethereumProvider;
  final SolanaWalletProvider? solanaProvider;

  const CryptoTopupWalletConnectionRequested({
    required this.walletType,
    this.ethereumProvider,
    this.solanaProvider,
  });

  @override
  List<Object?> get props => [walletType, ethereumProvider, solanaProvider];
}

/// Wallet successfully connected
class CryptoTopupWalletConnected extends CryptoTopupEvent {
  final String address;
  final int? chainId;
  final WalletType walletType;

  const CryptoTopupWalletConnected({
    required this.address,
    this.chainId,
    required this.walletType,
  });

  @override
  List<Object?> get props => [address, chainId, walletType];
}

/// Wallet connection failed
class CryptoTopupWalletConnectionFailed extends CryptoTopupEvent {
  final String error;
  final bool isUserRejected;
  final bool isNotInstalled;

  const CryptoTopupWalletConnectionFailed({
    required this.error,
    this.isUserRejected = false,
    this.isNotInstalled = false,
  });

  @override
  List<Object?> get props => [error, isUserRejected, isNotInstalled];
}

/// Wallet disconnected
class CryptoTopupWalletDisconnected extends CryptoTopupEvent {
  const CryptoTopupWalletDisconnected();
}

/// User's wallet account changed (different address)
class CryptoTopupAccountChanged extends CryptoTopupEvent {
  final String newAddress;
  final String? oldAddress;

  const CryptoTopupAccountChanged({
    required this.newAddress,
    this.oldAddress,
  });

  @override
  List<Object?> get props => [newAddress, oldAddress];
}

// ============================================
// AO Connect Signature Events (for ARIO via ETH)
// ============================================

/// Request AO connect signature for ARIO via Ethereum
class CryptoTopupAOConnectSignatureRequested extends CryptoTopupEvent {
  const CryptoTopupAOConnectSignatureRequested();
}

/// AO connect signature completed successfully
class CryptoTopupAOConnectSignatureCompleted extends CryptoTopupEvent {
  final String publicKey;

  const CryptoTopupAOConnectSignatureCompleted(this.publicKey);

  @override
  List<Object?> get props => [publicKey];
}

/// AO connect signature failed
class CryptoTopupAOConnectSignatureFailed extends CryptoTopupEvent {
  final String error;
  final bool isUserRejected;

  const CryptoTopupAOConnectSignatureFailed({
    required this.error,
    this.isUserRejected = false,
  });

  @override
  List<Object?> get props => [error, isUserRejected];
}

// ============================================
// Amount Entry Events
// ============================================

/// User changed the payment amount
class CryptoTopupAmountChanged extends CryptoTopupEvent {
  final double amount;
  final bool isUsd;

  const CryptoTopupAmountChanged({
    required this.amount,
    required this.isUsd,
  });

  @override
  List<Object?> get props => [amount, isUsd];
}

/// Toggle between USD and token input mode
class CryptoTopupInputModeChanged extends CryptoTopupEvent {
  final bool isUsdMode;

  const CryptoTopupInputModeChanged(this.isUsdMode);

  @override
  List<Object?> get props => [isUsdMode];
}

/// User submitted a promo code
class CryptoTopupPromoCodeSubmitted extends CryptoTopupEvent {
  final String code;

  const CryptoTopupPromoCodeSubmitted(this.code);

  @override
  List<Object?> get props => [code];
}

/// Clear promo code
class CryptoTopupPromoCodeCleared extends CryptoTopupEvent {
  const CryptoTopupPromoCodeCleared();
}

/// Request to refresh the quote
class CryptoTopupQuoteRefreshRequested extends CryptoTopupEvent {
  const CryptoTopupQuoteRefreshRequested();
}

/// Quote was refreshed (internal event)
class CryptoTopupQuoteRefreshed extends CryptoTopupEvent {
  final CryptoQuote newQuote;

  const CryptoTopupQuoteRefreshed(this.newQuote);

  @override
  List<Object?> get props => [newQuote];
}

// ============================================
// Confirmation Events
// ============================================

/// User wants to proceed to confirmation
class CryptoTopupProceedToConfirmation extends CryptoTopupEvent {
  const CryptoTopupProceedToConfirmation();
}

// ============================================
// Network Switch Events
// ============================================

/// Request network switch
class CryptoTopupNetworkSwitchRequested extends CryptoTopupEvent {
  final int targetChainId;

  const CryptoTopupNetworkSwitchRequested(this.targetChainId);

  @override
  List<Object?> get props => [targetChainId];
}

/// Network switch completed
class CryptoTopupNetworkSwitchCompleted extends CryptoTopupEvent {
  final int newChainId;

  const CryptoTopupNetworkSwitchCompleted(this.newChainId);

  @override
  List<Object?> get props => [newChainId];
}

/// Network switch failed
class CryptoTopupNetworkSwitchFailed extends CryptoTopupEvent {
  final String error;

  const CryptoTopupNetworkSwitchFailed(this.error);

  @override
  List<Object?> get props => [error];
}

/// Request to add network to wallet
class CryptoTopupNetworkAddRequested extends CryptoTopupEvent {
  final CryptoToken token;

  const CryptoTopupNetworkAddRequested(this.token);

  @override
  List<Object?> get props => [token];
}

/// Network add completed
class CryptoTopupNetworkAddCompleted extends CryptoTopupEvent {
  const CryptoTopupNetworkAddCompleted();
}

/// Network add failed
class CryptoTopupNetworkAddFailed extends CryptoTopupEvent {
  final String error;

  const CryptoTopupNetworkAddFailed(this.error);

  @override
  List<Object?> get props => [error];
}

/// User clicked "I've Switched" to verify manual network switch
class CryptoTopupManualNetworkCheckRequested extends CryptoTopupEvent {
  const CryptoTopupManualNetworkCheckRequested();
}

// ============================================
// Payment Events
// ============================================

/// User confirmed payment
class CryptoTopupPaymentConfirmed extends CryptoTopupEvent {
  const CryptoTopupPaymentConfirmed();
}

/// Payment succeeded
class CryptoTopupPaymentSucceeded extends CryptoTopupEvent {
  final String txId;
  final BigInt creditsAdded;

  const CryptoTopupPaymentSucceeded({
    required this.txId,
    required this.creditsAdded,
  });

  @override
  List<Object?> get props => [txId, creditsAdded];
}

/// Payment failed
class CryptoTopupPaymentFailed extends CryptoTopupEvent {
  final String error;
  final String? txId;
  final bool canRetry;
  final bool isUserRejected;

  const CryptoTopupPaymentFailed({
    required this.error,
    this.txId,
    this.canRetry = true,
    this.isUserRejected = false,
  });

  @override
  List<Object?> get props => [error, txId, canRetry, isUserRejected];
}

/// Retry a pending transaction
class CryptoTopupRetryTransaction extends CryptoTopupEvent {
  final String txId;

  const CryptoTopupRetryTransaction(this.txId);

  @override
  List<Object?> get props => [txId];
}

// ============================================
// Price Volatility Events
// ============================================

/// User accepted the price volatility (>5% change)
class CryptoTopupPriceVolatilityAccepted extends CryptoTopupEvent {
  const CryptoTopupPriceVolatilityAccepted();
}

/// User rejected the price change
class CryptoTopupPriceVolatilityRejected extends CryptoTopupEvent {
  const CryptoTopupPriceVolatilityRejected();
}

// ============================================
// Session Events
// ============================================

/// Session expired (25 minutes)
class CryptoTopupSessionExpired extends CryptoTopupEvent {
  const CryptoTopupSessionExpired();
}

/// Concurrent session detected in another tab
class CryptoTopupConcurrentSessionDetected extends CryptoTopupEvent {
  const CryptoTopupConcurrentSessionDetected();
}

/// User chose to take over the session from another tab
class CryptoTopupTakeOverSession extends CryptoTopupEvent {
  const CryptoTopupTakeOverSession();
}

// ============================================
// Balance Events
// ============================================

/// Token balance was fetched
class CryptoTopupBalanceFetched extends CryptoTopupEvent {
  final TokenBalance balance;

  const CryptoTopupBalanceFetched(this.balance);

  @override
  List<Object?> get props => [balance];
}

/// Request to refresh token balance
class CryptoTopupRefreshBalance extends CryptoTopupEvent {
  const CryptoTopupRefreshBalance();
}

// ============================================
// UI-Friendly Event Aliases
// ============================================

/// UI-friendly alias for selecting a token
class CryptoTopupSelectToken extends CryptoTopupEvent {
  final CryptoToken token;
  const CryptoTopupSelectToken(this.token);
  @override
  List<Object?> get props => [token];
}

/// UI-friendly alias for connecting wallet
class CryptoTopupConnectWallet extends CryptoTopupEvent {
  final EthereumWalletProvider? ethereumProvider;
  final SolanaWalletProvider? solanaProvider;

  const CryptoTopupConnectWallet({
    this.ethereumProvider,
    this.solanaProvider,
  });

  @override
  List<Object?> get props => [ethereumProvider, solanaProvider];
}

/// Go back to previous step
class CryptoTopupGoBack extends CryptoTopupEvent {
  const CryptoTopupGoBack();
}

/// Update payment amount
class CryptoTopupUpdateAmount extends CryptoTopupEvent {
  final double amount;

  /// Whether the amount is in USD. If false, amount is in token units.
  /// Defaults to true for backwards compatibility.
  final bool isUsd;

  const CryptoTopupUpdateAmount(this.amount, {this.isUsd = true});

  @override
  List<Object?> get props => [amount, isUsd];
}

/// Toggle between USD and token input mode
class CryptoTopupToggleAmountMode extends CryptoTopupEvent {
  const CryptoTopupToggleAmountMode();
}

/// Refresh the quote
class CryptoTopupRefreshQuote extends CryptoTopupEvent {
  const CryptoTopupRefreshQuote();
}

/// Apply a promo code
class CryptoTopupApplyPromoCode extends CryptoTopupEvent {
  final String code;
  const CryptoTopupApplyPromoCode(this.code);
  @override
  List<Object?> get props => [code];
}

/// Remove promo code
class CryptoTopupRemovePromoCode extends CryptoTopupEvent {
  const CryptoTopupRemovePromoCode();
}

/// Confirm the payment
class CryptoTopupConfirmPayment extends CryptoTopupEvent {
  const CryptoTopupConfirmPayment();
}

/// Switch to required network
class CryptoTopupSwitchNetwork extends CryptoTopupEvent {
  final int chainId;
  const CryptoTopupSwitchNetwork(this.chainId);
  @override
  List<Object?> get props => [chainId];
}

/// Show manual network switch instructions
class CryptoTopupShowManualNetworkSwitch extends CryptoTopupEvent {
  const CryptoTopupShowManualNetworkSwitch();
}

/// Retry after error
class CryptoTopupRetry extends CryptoTopupEvent {
  const CryptoTopupRetry();
}

/// Close the modal
class CryptoTopupClose extends CryptoTopupEvent {
  const CryptoTopupClose();
}

/// Resume a pending transaction
class CryptoTopupResumePendingTransaction extends CryptoTopupEvent {
  const CryptoTopupResumePendingTransaction();
}

/// Cancel account change (revert to previous account)
class CryptoTopupCancelAccountChange extends CryptoTopupEvent {
  const CryptoTopupCancelAccountChange();
}

/// Accept new account after change
class CryptoTopupAcceptAccountChange extends CryptoTopupEvent {
  const CryptoTopupAcceptAccountChange();
}

/// Reject new quote after price change
class CryptoTopupRejectNewQuote extends CryptoTopupEvent {
  const CryptoTopupRejectNewQuote();
}

/// Accept new quote after price change
class CryptoTopupAcceptNewQuote extends CryptoTopupEvent {
  const CryptoTopupAcceptNewQuote();
}
