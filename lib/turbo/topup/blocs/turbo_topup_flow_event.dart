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
  TurboTopUpShowPaymentFormView(super.stepNumber);
}

// show payment review
class TurboTopUpShowPaymentReviewView extends TurboTopupFlowEvent {
  const TurboTopUpShowPaymentReviewView({
    required this.paymentUserInformation,
  }) : super(3);

  final PaymentUserInformation paymentUserInformation;
}

// show success
class TurboTopUpShowSuccessView extends TurboTopupFlowEvent {
  const TurboTopUpShowSuccessView() : super(4);
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
