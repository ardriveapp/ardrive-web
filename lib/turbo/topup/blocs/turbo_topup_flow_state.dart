part of 'turbo_topup_flow_bloc.dart';

abstract class TurboTopupFlowState extends Equatable {
  const TurboTopupFlowState(
    this.isMovingForward,
  );

  final bool isMovingForward;

  @override
  List<Object> get props => [];
}

class TurboTopupFlowInitial extends TurboTopupFlowState {
  const TurboTopupFlowInitial() : super(true);
}

class TurboTopupFlowShowingEstimationView extends TurboTopupFlowState {
  const TurboTopupFlowShowingEstimationView({bool isMovingForward = true})
      : super(isMovingForward);
}

class TurboTopupFlowShowingPaymentFormView extends TurboTopupFlowState {
  final PriceEstimate priceEstimate;

  const TurboTopupFlowShowingPaymentFormView({
    bool isMovingForward = true,
    required this.priceEstimate,
  }) : super(isMovingForward);
}

class TurboTopupFlowShowingPaymentReviewView extends TurboTopupFlowState {
  final PriceEstimate priceEstimate;

  const TurboTopupFlowShowingPaymentReviewView({
    bool isMovingForward = true,
    required this.priceEstimate,
  }) : super(isMovingForward);
}

class TurboTopupFlowShowingSuccessView extends TurboTopupFlowState {
  /// Amount paid (formatted, e.g., "$25.00")
  final String? amountPaid;

  /// Credits received (formatted, e.g., "0.25 AR")
  final String? creditsReceived;

  /// Storage estimate for credits received (e.g., "2.5 GB")
  final String? storageEstimate;

  /// New balance after purchase (formatted credits, e.g., "0.75 Credits")
  final String? newBalanceCredits;

  /// New balance after purchase (formatted storage, e.g., "7.5 GB")
  final String? newBalanceStorage;

  const TurboTopupFlowShowingSuccessView({
    bool isMovingForward = true,
    this.amountPaid,
    this.creditsReceived,
    this.storageEstimate,
    this.newBalanceCredits,
    this.newBalanceStorage,
  }) : super(isMovingForward);

  @override
  List<Object> get props => [
        isMovingForward,
        amountPaid ?? '',
        creditsReceived ?? '',
        storageEstimate ?? '',
        newBalanceCredits ?? '',
        newBalanceStorage ?? '',
      ];
}

class TurboTopupFlowShowingErrorView extends TurboTopupFlowState {
  final TurboErrorType errorType;
  const TurboTopupFlowShowingErrorView({
    bool isMovingForward = true,
    required this.errorType,
  }) : super(isMovingForward);
}

class TurboTopUpShowingSessionExpiredView extends TurboTopupFlowState {
  const TurboTopUpShowingSessionExpiredView({bool isMovingForward = true})
      : super(isMovingForward);
}

class TurboTopupFlowShowingCryptoView extends TurboTopupFlowState {
  final CryptoToken token;
  final double amount;

  /// Current Turbo balance (in winc) for display on checkout
  final BigInt currentTurboBalance;

  /// Current balance storage estimate (e.g., "5.2 GB")
  final String currentBalanceStorage;

  /// Credits to receive (in winc) for calculating new balance
  final BigInt creditsToReceive;

  /// New balance storage estimate (e.g., "7.3 GB")
  final String newBalanceStorage;

  const TurboTopupFlowShowingCryptoView({
    bool isMovingForward = true,
    required this.token,
    required this.amount,
    required this.currentTurboBalance,
    required this.currentBalanceStorage,
    required this.creditsToReceive,
    required this.newBalanceStorage,
  }) : super(isMovingForward);

  @override
  List<Object> get props => [
        isMovingForward,
        token,
        amount,
        currentTurboBalance,
        currentBalanceStorage,
        creditsToReceive,
        newBalanceStorage,
      ];
}

enum TurboErrorType {
  network,
  server,
  unknown,
  sessionExpired,
  paymentFailed,
  fetchPaymentIntentFailed,
  fetchEstimationInformationFailed,
}
