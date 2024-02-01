import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:equatable/equatable.dart';

class PriceEstimate extends Equatable {
  final PriceForFiat estimate;
  final double priceInCurrency;
  final double estimatedStorage;

  const PriceEstimate({
    required this.estimate,
    required this.priceInCurrency,
    required this.estimatedStorage,
  });

  bool get hasPromoCodeApplied => estimate.adjustments.isNotEmpty;
  String? get humanReadableDiscountPercentage =>
      estimate.humanReadableDiscountPercentage;
  double get paymentAmount => hasPromoCodeApplied
      ? estimate.actualPaymentAmount! / 100
      : priceInCurrency;
  BigInt get winstonCredits => estimate.winstonCredits;
  bool get hasReachedMaximumDiscount => estimate.hasReachedMaximumDiscount;
  String? get adjustmentAmount => estimate.adjustmentAmount;

  factory PriceEstimate.zero() => PriceEstimate(
        estimate: PriceForFiat.zero(),
        priceInCurrency: 0,
        estimatedStorage: 0,
      );

  @override
  String toString() {
    return 'PriceEstimate{estimate: $estimate,'
        ' priceInCurrency: $priceInCurrency,'
        ' estimatedStorage: $estimatedStorage}';
  }

  @override
  List<Object> get props => [
        estimate,
        priceInCurrency,
        estimatedStorage,
      ];
}
