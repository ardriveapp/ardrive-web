part of 'payment_review_bloc.dart';

abstract class PaymentReviewEvent extends Equatable {
  const PaymentReviewEvent();

  @override
  List<Object> get props => [];
}

class PaymentReviewFinishPayment extends PaymentReviewEvent {
  final String? email;

  const PaymentReviewFinishPayment({this.email});

  @override
  List<Object> get props => [];
}

class PaymentReviewRefreshQuote extends PaymentReviewEvent {
  @override
  List<Object> get props => [];
}

class PaymentReviewLoadPaymentModel extends PaymentReviewEvent {
  @override
  List<Object> get props => [];
}
