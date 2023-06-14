part of 'payment_review_bloc.dart';

abstract class PaymentReviewState extends Equatable {
  const PaymentReviewState();

  @override
  List<Object> get props => [];
}

class PaymentReviewInitial extends PaymentReviewState {}

class PaymentReviewLoading extends PaymentReviewPaymentModelLoaded {
  const PaymentReviewLoading({
    required super.quoteExpirationDate,
    required super.total,
    required super.subTotal,
    required super.credits,
  });
}

class PaymentReviewLoadingPaymentModel extends PaymentReviewState {
  const PaymentReviewLoadingPaymentModel();
}

class PaymentReviewPaymentModelLoaded extends PaymentReviewState {
  final String total;
  final String subTotal;
  final String credits;
  final DateTime quoteExpirationDate;

  const PaymentReviewPaymentModelLoaded({
    required this.total,
    required this.subTotal,
    required this.credits,
    required this.quoteExpirationDate,
  });

  PaymentReviewPaymentModelLoaded copyWith({
    String? total,
    String? subTotal,
    String? credits,
    DateTime? quoteExpirationDate,
  }) {
    return PaymentReviewPaymentModelLoaded(
      total: total ?? this.total,
      subTotal: subTotal ?? this.subTotal,
      credits: credits ?? this.credits,
      quoteExpirationDate: quoteExpirationDate ?? this.quoteExpirationDate,
    );
  }
}

class PaymentReviewLoadingQuote extends PaymentReviewPaymentModelLoaded {
  const PaymentReviewLoadingQuote({
    required super.quoteExpirationDate,
    required super.total,
    required super.subTotal,
    required super.credits,
  });
}

class PaymentReviewQuoteLoaded extends PaymentReviewPaymentModelLoaded {
  const PaymentReviewQuoteLoaded({
    required super.quoteExpirationDate,
    required super.total,
    required super.subTotal,
    required super.credits,
  });
}

class PaymentReviewQuoteError extends PaymentReviewPaymentModelLoaded {
  final TurboErrorType errorType;
  const PaymentReviewQuoteError({
    required this.errorType,
    required String total,
    required String subTotal,
    required String credits,
    required DateTime quoteExpirationDate,
  }) : super(
          total: total,
          subTotal: subTotal,
          credits: credits,
          quoteExpirationDate: quoteExpirationDate,
        );
}

class PaymentReviewPaymentSuccess extends PaymentReviewPaymentModelLoaded {
  const PaymentReviewPaymentSuccess({
    required super.quoteExpirationDate,
    required super.total,
    required super.subTotal,
    required super.credits,
  });
}

class PaymentReviewError extends PaymentReviewState {
  final TurboErrorType errorType;
  const PaymentReviewError({
    required this.errorType,
  });
}

class PaymentReviewPaymentError extends PaymentReviewPaymentModelLoaded {
  final TurboErrorType errorType;

  const PaymentReviewPaymentError({
    required super.quoteExpirationDate,
    required super.total,
    required super.subTotal,
    required super.credits,
    required this.errorType,
  });
}

class PaymentReviewErrorLoadingPaymentModel extends PaymentReviewError {
  const PaymentReviewErrorLoadingPaymentModel({required super.errorType});
}
