part of 'payment_review_bloc.dart';

abstract class PaymentReviewEvent extends Equatable {
  const PaymentReviewEvent();

  @override
  List<Object> get props => [];
}

class PaymentReviewFinishPayment extends PaymentReviewEvent {
  final PaymentUserInformation paymentUserInformation;

  const PaymentReviewFinishPayment({
    required this.paymentUserInformation,
  });

  @override
  List<Object> get props => [paymentUserInformation];
}

class PaymentReviewRefreshQuote extends PaymentReviewEvent {}

class PaymentReviewLoadPaymentModel extends PaymentReviewEvent {}
