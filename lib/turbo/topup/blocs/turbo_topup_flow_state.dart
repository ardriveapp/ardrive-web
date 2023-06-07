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

  const TurboTopupFlowShowingPaymentFormView(
      {bool isMovingForward = true, required this.priceEstimate})
      : super(isMovingForward);
}

class TurboTopupFlowShowingPaymentReviewView extends TurboTopupFlowState {
  const TurboTopupFlowShowingPaymentReviewView({bool isMovingForward = true})
      : super(isMovingForward);
}

class TurboTopupFlowShowingSuccessView extends TurboTopupFlowState {
  const TurboTopupFlowShowingSuccessView({bool isMovingForward = true})
      : super(isMovingForward);
}
