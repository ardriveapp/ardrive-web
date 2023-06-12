part of 'payment_review_bloc.dart';

abstract class PaymentReviewState extends Equatable {
  const PaymentReviewState({required this.paymentUserInformation});

  final PaymentUserInformation paymentUserInformation;

  @override
  List<Object> get props => [paymentUserInformation];
}

class PaymentReviewInitial extends PaymentReviewState {
  const PaymentReviewInitial(PaymentUserInformation paymentUserInformation)
      : super(paymentUserInformation: paymentUserInformation);
}

class PaymentReviewLoading extends PaymentReviewPaymentModelLoaded {
  const PaymentReviewLoading({
    required super.paymentUserInformation,
    required super.quoteExpirationDate,
    required super.total,
    required super.subTotal,
    required super.credits,
  });
}

class PaymentReviewLoadingPaymentModel extends PaymentReviewState {
  const PaymentReviewLoadingPaymentModel(
      PaymentUserInformation paymentUserInformation)
      : super(paymentUserInformation: paymentUserInformation);
}

class PaymentReviewPaymentModelLoaded extends PaymentReviewState {
  final String total;
  final String subTotal;
  final String credits;
  final DateTime quoteExpirationDate;

  const PaymentReviewPaymentModelLoaded({
    required PaymentUserInformation paymentUserInformation,
    required this.total,
    required this.subTotal,
    required this.credits,
    required this.quoteExpirationDate,
  }) : super(paymentUserInformation: paymentUserInformation);

  PaymentReviewPaymentModelLoaded copyWith({
    String? total,
    String? subTotal,
    String? credits,
    DateTime? quoteExpirationDate,
  }) {
    return PaymentReviewPaymentModelLoaded(
      paymentUserInformation: paymentUserInformation,
      total: total ?? this.total,
      subTotal: subTotal ?? this.subTotal,
      credits: credits ?? this.credits,
      quoteExpirationDate: quoteExpirationDate ?? this.quoteExpirationDate,
    );
  }
}

class PaymentReviewLoadingQuote extends PaymentReviewPaymentModelLoaded {
  const PaymentReviewLoadingQuote({
    required super.paymentUserInformation,
    required super.quoteExpirationDate,
    required super.total,
    required super.subTotal,
    required super.credits,
  });
}

class PaymentReviewQuoteLoaded extends PaymentReviewPaymentModelLoaded {
  const PaymentReviewQuoteLoaded({
    required super.paymentUserInformation,
    required super.quoteExpirationDate,
    required super.total,
    required super.subTotal,
    required super.credits,
  });
}

class PaymentReviewQuoteError extends PaymentReviewPaymentModelLoaded {
  final TurboErrorType errorType;
  const PaymentReviewQuoteError({
    required PaymentUserInformation paymentUserInformation,
    required this.errorType,
    required String total,
    required String subTotal,
    required String credits,
    required DateTime quoteExpirationDate,
  }) : super(
          paymentUserInformation: paymentUserInformation,
          total: total,
          subTotal: subTotal,
          credits: credits,
          quoteExpirationDate: quoteExpirationDate,
        );
}

class PaymentReviewPaymentSuccess extends PaymentReviewPaymentModelLoaded {
  const PaymentReviewPaymentSuccess({
    required super.paymentUserInformation,
    required super.quoteExpirationDate,
    required super.total,
    required super.subTotal,
    required super.credits,
  });
}

class PaymentReviewError extends PaymentReviewState {
  final TurboErrorType errorType;
  const PaymentReviewError({
    required PaymentUserInformation paymentUserInformation,
    required this.errorType,
  }) : super(paymentUserInformation: paymentUserInformation);
}

class PaymentReviewPaymentError extends PaymentReviewError {
  const PaymentReviewPaymentError({
    required super.paymentUserInformation,
    required super.errorType,
  });
}

class PaymentReviewErrorLoadingPaymentModel extends PaymentReviewError {
  const PaymentReviewErrorLoadingPaymentModel({
    required super.paymentUserInformation,
  }) : super(errorType: TurboErrorType.fetchPaymentIntentFailed);
}
