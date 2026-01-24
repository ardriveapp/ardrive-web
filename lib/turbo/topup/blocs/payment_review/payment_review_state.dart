part of 'payment_review_bloc.dart';

abstract class PaymentReviewState extends Equatable {
  const PaymentReviewState();

  @override
  List<Object> get props => [];
}

class PaymentReviewInitial extends PaymentReviewState {
  const PaymentReviewInitial();
}

class PaymentReviewLoading extends PaymentReviewPaymentModelLoaded {
  PaymentReviewLoading({
    required super.quoteExpirationDate,
    required super.total,
    required super.subTotal,
    required super.credits,
    required super.promoDiscount,
    super.creditsWinc,
    super.currentBalance,
    super.storageEstimate,
    super.currentBalanceStorage,
    super.newBalanceStorage,
  });

  @override
  List<Object> get props => [
        quoteExpirationDate,
        total,
        subTotal ?? '',
        credits,
        promoDiscount ?? '',
      ];
}

class PaymentReviewLoadingPaymentModel extends PaymentReviewState {
  const PaymentReviewLoadingPaymentModel();
}

class PaymentReviewPaymentModelLoaded extends PaymentReviewState {
  final String total;
  final String? subTotal;
  final String credits;
  final String? promoDiscount;
  final DateTime quoteExpirationDate;

  /// Credits to receive in winc (for calculating new balance)
  final BigInt creditsWinc;

  /// Current Turbo balance in winc
  final BigInt currentBalance;

  /// Storage estimate for credits to receive
  final String storageEstimate;

  /// Storage estimate for current balance
  final String currentBalanceStorage;

  /// Storage estimate for new balance after purchase
  final String newBalanceStorage;

  PaymentReviewPaymentModelLoaded({
    required this.total,
    required this.subTotal,
    required this.credits,
    required this.promoDiscount,
    required this.quoteExpirationDate,
    BigInt? creditsWinc,
    BigInt? currentBalance,
    this.storageEstimate = '0 GB',
    this.currentBalanceStorage = '0 GB',
    this.newBalanceStorage = '0 GB',
  })  : creditsWinc = creditsWinc ?? BigInt.zero,
        currentBalance = currentBalance ?? BigInt.zero;

  /// New balance after purchase
  BigInt get newBalance => currentBalance + creditsWinc;

  PaymentReviewPaymentModelLoaded copyWith({
    String? total,
    String? subTotal,
    String? credits,
    DateTime? quoteExpirationDate,
    String? promoDiscount,
    BigInt? creditsWinc,
    BigInt? currentBalance,
    String? storageEstimate,
    String? currentBalanceStorage,
    String? newBalanceStorage,
  }) {
    return PaymentReviewPaymentModelLoaded(
      total: total ?? this.total,
      subTotal: subTotal ?? this.subTotal,
      credits: credits ?? this.credits,
      quoteExpirationDate: quoteExpirationDate ?? this.quoteExpirationDate,
      promoDiscount: promoDiscount ?? this.promoDiscount,
      creditsWinc: creditsWinc ?? this.creditsWinc,
      currentBalance: currentBalance ?? this.currentBalance,
      storageEstimate: storageEstimate ?? this.storageEstimate,
      currentBalanceStorage:
          currentBalanceStorage ?? this.currentBalanceStorage,
      newBalanceStorage: newBalanceStorage ?? this.newBalanceStorage,
    );
  }

  @override
  List<Object> get props => [
        total,
        subTotal ?? '',
        credits,
        promoDiscount ?? '',
        quoteExpirationDate,
        creditsWinc,
        currentBalance,
        storageEstimate,
        currentBalanceStorage,
        newBalanceStorage,
      ];
}

class PaymentReviewLoadingQuote extends PaymentReviewPaymentModelLoaded {
  PaymentReviewLoadingQuote({
    required super.quoteExpirationDate,
    required super.total,
    required super.subTotal,
    required super.credits,
    required super.promoDiscount,
    super.creditsWinc,
    super.currentBalance,
    super.storageEstimate,
    super.currentBalanceStorage,
    super.newBalanceStorage,
  });

  @override
  List<Object> get props => [
        quoteExpirationDate,
        total,
        subTotal ?? '',
        credits,
        promoDiscount ?? '',
      ];
}

class PaymentReviewQuoteLoaded extends PaymentReviewPaymentModelLoaded {
  PaymentReviewQuoteLoaded({
    required super.quoteExpirationDate,
    required super.total,
    required super.subTotal,
    required super.credits,
    required super.promoDiscount,
    super.creditsWinc,
    super.currentBalance,
    super.storageEstimate,
    super.currentBalanceStorage,
    super.newBalanceStorage,
  });

  @override
  List<Object> get props => [
        quoteExpirationDate,
        total,
        subTotal ?? '',
        credits,
        promoDiscount ?? '',
      ];
}

class PaymentReviewQuoteError extends PaymentReviewPaymentModelLoaded {
  final TurboErrorType errorType;
  PaymentReviewQuoteError({
    required this.errorType,
    required super.total,
    required super.subTotal,
    required super.credits,
    required super.quoteExpirationDate,
    required super.promoDiscount,
    super.creditsWinc,
    super.currentBalance,
    super.storageEstimate,
    super.currentBalanceStorage,
    super.newBalanceStorage,
  });

  @override
  List<Object> get props => [
        errorType,
        total,
        subTotal ?? '',
        credits,
        quoteExpirationDate,
        promoDiscount ?? '',
      ];
}

class PaymentReviewPaymentSuccess extends PaymentReviewPaymentModelLoaded {
  PaymentReviewPaymentSuccess({
    required super.quoteExpirationDate,
    required super.total,
    required super.subTotal,
    required super.credits,
    required super.promoDiscount,
    super.creditsWinc,
    super.currentBalance,
    super.storageEstimate,
    super.currentBalanceStorage,
    super.newBalanceStorage,
  });

  @override
  List<Object> get props => [
        quoteExpirationDate,
        total,
        subTotal ?? '',
        credits,
        promoDiscount ?? '',
      ];
}

class PaymentReviewError extends PaymentReviewState {
  final TurboErrorType errorType;
  const PaymentReviewError({
    required this.errorType,
  });

  @override
  List<Object> get props => [
        errorType,
      ];
}

class PaymentReviewPaymentError extends PaymentReviewPaymentModelLoaded {
  final TurboErrorType errorType;

  PaymentReviewPaymentError({
    required super.quoteExpirationDate,
    required super.total,
    required super.subTotal,
    required super.credits,
    required this.errorType,
    required super.promoDiscount,
    super.creditsWinc,
    super.currentBalance,
    super.storageEstimate,
    super.currentBalanceStorage,
    super.newBalanceStorage,
  });

  @override
  List<Object> get props => [
        quoteExpirationDate,
        total,
        subTotal ?? '',
        credits,
        errorType,
        promoDiscount ?? '',
      ];
}

class PaymentReviewErrorLoadingPaymentModel extends PaymentReviewError {
  const PaymentReviewErrorLoadingPaymentModel({
    required super.errorType,
  });

  @override
  List<Object> get props => [
        errorType,
      ];
}
