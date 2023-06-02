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
  const TurboTopUpShowPaymentFormView() : super(2);
}
