part of 'turbo_topup_flow_bloc.dart';

abstract class TurboTopupFlowEvent extends Equatable {
  const TurboTopupFlowEvent(
    this.stepNumber,
  );

  final int stepNumber;

  @override
  List<Object> get props => [];
}

// show estimation view
class TurboTopUpShowEstimationView extends TurboTopupFlowEvent {
  const TurboTopUpShowEstimationView() : super(1);
}

// show payment form
class TurboTopUpShowPaymentFormView extends TurboTopupFlowEvent {
  const TurboTopUpShowPaymentFormView(super.stepNumber);
}

// show payment review
class TurboTopUpShowPaymentReviewView extends TurboTopupFlowEvent {
  const TurboTopUpShowPaymentReviewView({
    required this.name,
    required this.country,
  }) : super(3);

  final String name;
  final String country;
}

// show success
class TurboTopUpShowSuccessView extends TurboTopupFlowEvent {
  /// Amount paid (formatted, e.g., "$25.00")
  final String? amountPaid;

  /// Credits received (formatted, e.g., "0.25 AR")
  final String? creditsReceived;

  /// Storage estimate for credits received (e.g., "2.5 GB")
  final String? storageEstimate;

  /// New balance after purchase (formatted storage, e.g., "7.5 GB")
  final String? newBalanceStorage;

  const TurboTopUpShowSuccessView({
    this.amountPaid,
    this.creditsReceived,
    this.storageEstimate,
    this.newBalanceStorage,
  }) : super(4);

  @override
  List<Object> get props => [
        amountPaid ?? '',
        creditsReceived ?? '',
        storageEstimate ?? '',
        newBalanceStorage ?? '',
      ];
}

class TurboTopUpPay extends TurboTopupFlowEvent {
  final String? email;
  final PaymentUserInformation? paymentUserInformation;

  const TurboTopUpPay({
    this.email,
    this.paymentUserInformation,
  }) : super(4);
}

class TurboTopUpShowSessionExpiredView extends TurboTopupFlowEvent {
  const TurboTopUpShowSessionExpiredView() : super(0);
}

class TurboTopUpShowErrorView extends TurboTopupFlowEvent {
  final TurboErrorType errorType;

  const TurboTopUpShowErrorView(this.errorType) : super(0);
}

// show crypto payment flow
class TurboTopUpShowCryptoView extends TurboTopupFlowEvent {
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

  const TurboTopUpShowCryptoView({
    required this.token,
    required this.amount,
    required this.currentTurboBalance,
    required this.currentBalanceStorage,
    required this.creditsToReceive,
    required this.newBalanceStorage,
  }) : super(2);

  @override
  List<Object> get props => [
        token,
        amount,
        currentTurboBalance,
        currentBalanceStorage,
        creditsToReceive,
        newBalanceStorage,
      ];
}
