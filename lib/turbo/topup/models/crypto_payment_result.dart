import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:equatable/equatable.dart';

/// Status of a cryptocurrency payment
enum CryptoPaymentStatus {
  /// Payment completed successfully
  success,

  /// Payment is pending blockchain confirmation
  pending,

  /// Payment failed
  failed,

  /// User rejected the transaction in their wallet
  userRejected,

  /// Insufficient token balance
  insufficientFunds,

  /// Insufficient balance for gas fees
  insufficientGas,

  /// Network connection error
  networkError,

  /// User is on the wrong network
  wrongNetwork,

  /// Quote expired before payment was completed
  quoteExpired,

  /// Transaction was submitted but confirmation timed out
  confirmationTimeout,
}

/// Extension methods for [CryptoPaymentStatus]
extension CryptoPaymentStatusX on CryptoPaymentStatus {
  /// Whether this status allows the user to retry
  bool get canRetry => switch (this) {
        CryptoPaymentStatus.success || CryptoPaymentStatus.pending => false,
        CryptoPaymentStatus.insufficientFunds ||
        CryptoPaymentStatus.insufficientGas =>
          false,
        _ => true,
      };

  /// Whether this status represents a final state (no further state changes expected)
  bool get isFinal => switch (this) {
        CryptoPaymentStatus.success ||
        CryptoPaymentStatus.failed ||
        CryptoPaymentStatus.userRejected ||
        CryptoPaymentStatus.insufficientFunds ||
        CryptoPaymentStatus.wrongNetwork ||
        CryptoPaymentStatus.quoteExpired ||
        CryptoPaymentStatus.confirmationTimeout =>
          true,
        // Non-final: pending, networkError, insufficientGas (retryable)
        _ => false,
      };

  /// Human-readable error title
  String get errorTitle => switch (this) {
        CryptoPaymentStatus.success => 'Payment Complete',
        CryptoPaymentStatus.pending => 'Payment Pending',
        CryptoPaymentStatus.failed => 'Payment Failed',
        CryptoPaymentStatus.userRejected => 'Payment Cancelled',
        CryptoPaymentStatus.insufficientFunds => 'Insufficient Funds',
        CryptoPaymentStatus.insufficientGas => 'Insufficient Funds for Gas',
        CryptoPaymentStatus.networkError => 'Network Error',
        CryptoPaymentStatus.wrongNetwork => 'Wrong Network',
        CryptoPaymentStatus.quoteExpired => 'Quote Expired',
        CryptoPaymentStatus.confirmationTimeout => 'Transaction Pending',
      };

  /// Human-readable error message
  String get errorMessage => switch (this) {
        CryptoPaymentStatus.success => 'Your credits have been added.',
        CryptoPaymentStatus.pending => 'Waiting for blockchain confirmation...',
        CryptoPaymentStatus.failed =>
          'The transaction failed on the blockchain.',
        CryptoPaymentStatus.userRejected =>
          'You cancelled the transaction in your wallet.',
        CryptoPaymentStatus.insufficientFunds =>
          'You don\'t have enough tokens to complete this payment.',
        CryptoPaymentStatus.insufficientGas =>
          'You need additional funds for network fees.',
        CryptoPaymentStatus.networkError =>
          'Could not connect to the blockchain. Please check your connection.',
        CryptoPaymentStatus.wrongNetwork =>
          'Please switch to the correct network in your wallet.',
        CryptoPaymentStatus.quoteExpired =>
          'The price quote has expired. Please try again for a new quote.',
        CryptoPaymentStatus.confirmationTimeout =>
          'Your payment was submitted but we couldn\'t confirm it was received.',
      };
}

/// Result of a cryptocurrency payment attempt
class CryptoPaymentResult extends Equatable {
  /// Whether the payment was successful
  final bool success;

  /// Transaction ID (blockchain tx hash)
  final String? transactionId;

  /// Error message if payment failed
  final String? errorMessage;

  /// Status of the payment
  final CryptoPaymentStatus status;

  /// The token used for payment
  final CryptoToken? token;

  /// Credits added (on success)
  final double? creditsAdded;

  /// New balance after payment (on success)
  final double? newBalance;

  const CryptoPaymentResult({
    required this.success,
    this.transactionId,
    this.errorMessage,
    required this.status,
    this.token,
    this.creditsAdded,
    this.newBalance,
  });

  /// Create a successful result
  factory CryptoPaymentResult.success({
    required String transactionId,
    required CryptoToken token,
    required double creditsAdded,
    required double newBalance,
  }) {
    return CryptoPaymentResult(
      success: true,
      transactionId: transactionId,
      status: CryptoPaymentStatus.success,
      token: token,
      creditsAdded: creditsAdded,
      newBalance: newBalance,
    );
  }

  /// Create a pending result (transaction submitted, awaiting confirmation)
  factory CryptoPaymentResult.pending({
    required String transactionId,
    required CryptoToken token,
  }) {
    return CryptoPaymentResult(
      success: false,
      transactionId: transactionId,
      status: CryptoPaymentStatus.pending,
      token: token,
    );
  }

  /// Create a failure result
  factory CryptoPaymentResult.failure({
    required CryptoPaymentStatus status,
    String? errorMessage,
    String? transactionId,
    CryptoToken? token,
  }) {
    return CryptoPaymentResult(
      success: false,
      transactionId: transactionId,
      errorMessage: errorMessage ?? status.errorMessage,
      status: status,
      token: token,
    );
  }

  /// Whether the payment can be retried
  bool get canRetry => status.canRetry;

  /// Whether the transaction has a transaction ID (for viewing on explorer)
  bool get hasTransactionId =>
      transactionId != null && transactionId!.isNotEmpty;

  @override
  List<Object?> get props => [
        success,
        transactionId,
        errorMessage,
        status,
        token,
        creditsAdded,
        newBalance,
      ];

  @override
  String toString() {
    return 'CryptoPaymentResult{success: $success, status: $status, '
        'transactionId: $transactionId, creditsAdded: $creditsAdded}';
  }
}
