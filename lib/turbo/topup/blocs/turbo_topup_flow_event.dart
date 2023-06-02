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

// show payment review
class TurboTopUpShowPaymentReviewView extends TurboTopupFlowEvent {
  const TurboTopUpShowPaymentReviewView() : super(3);
}

// show success
class TurboTopUpShowSuccessView extends TurboTopupFlowEvent {
  const TurboTopUpShowSuccessView() : super(4);
}
