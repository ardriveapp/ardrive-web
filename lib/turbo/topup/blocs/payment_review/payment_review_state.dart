part of 'payment_review_bloc.dart';

abstract class PaymentReviewState extends Equatable {
  const PaymentReviewState(
    this.priceEstimate,
    this.paymentUserInformation,
  );

  final PriceEstimate priceEstimate;
  final PaymentUserInformation paymentUserInformation;

  double get fee => priceEstimate.priceInCurrency * 0.05;
  double get taxes => priceEstimate.priceInCurrency * 0.1;
  double get total => priceEstimate.priceInCurrency + fee + taxes;

  @override
  List<Object> get props => [];
}

class PaymentReviewInitial extends PaymentReviewState {
  const PaymentReviewInitial(super.priceEstimate, super.paymentUserInformation);
}

class PaymentReviewLoading extends PaymentReviewState {
  const PaymentReviewLoading(super.priceEstimate, super.paymentUserInformation);
}

class PaymentReviewLoadingQuote extends PaymentReviewState {
  const PaymentReviewLoadingQuote(
      super.priceEstimate, super.paymentUserInformation);
}

class PaymentReviewQuoteLoaded extends PaymentReviewState {
  const PaymentReviewQuoteLoaded(
      super.priceEstimate, super.paymentUserInformation);
}

class PaymentReviewQuoteError extends PaymentReviewState {
  final TurboErrorType errorType;
  const PaymentReviewQuoteError(
      super.priceEstimate, super.paymentUserInformation, this.errorType);
}

class PaymentReviewPaymentSuccess extends PaymentReviewState {
  const PaymentReviewPaymentSuccess(
      super.priceEstimate, super.paymentUserInformation);
}

class PaymentReviewPaymentError extends PaymentReviewState {
  final TurboErrorType errorType;
  const PaymentReviewPaymentError(
      super.priceEstimate, super.paymentUserInformation, this.errorType);
}
