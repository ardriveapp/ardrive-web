import 'package:equatable/equatable.dart';

class PriceEstimate extends Equatable {
  final BigInt credits;
  final double priceInCurrency;
  final double estimatedStorage;
  final double promoDiscountFactor;

  const PriceEstimate({
    required this.credits,
    required this.priceInCurrency,
    required this.estimatedStorage,
    required this.promoDiscountFactor,
  });

  factory PriceEstimate.zero() => PriceEstimate(
        credits: BigInt.from(0),
        priceInCurrency: 0,
        estimatedStorage: 0,
        promoDiscountFactor: 0,
      );

  @override
  String toString() {
    return 'PriceEstimate{credits: $credits, priceInCurrency: $priceInCurrency,'
        ' estimatedStorage: $estimatedStorage,'
        ' promoDiscountFactor: $promoDiscountFactor}';
  }

  @override
  List<Object?> get props => [
        credits,
        priceInCurrency,
        estimatedStorage,
        promoDiscountFactor,
      ];
}
