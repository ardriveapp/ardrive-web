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
  const TurboTopupFlowShowingSuccessView({bool isMovingForward = true})
      : super(isMovingForward);
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

  const TurboTopupFlowShowingCryptoView({
    bool isMovingForward = true,
    required this.token,
    required this.amount,
  }) : super(isMovingForward);

  @override
  List<Object> get props => [isMovingForward, token, amount];
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
