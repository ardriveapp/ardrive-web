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
  const TurboTopupFlowShowingPaymentFormView({bool isMovingForward = true})
      : super(isMovingForward);
}
