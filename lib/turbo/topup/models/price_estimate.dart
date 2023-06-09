import 'package:equatable/equatable.dart';

class PriceEstimate extends Equatable {
  final BigInt credits;
  final int priceInCurrency;
  final double estimatedStorage;

  const PriceEstimate({
    required this.credits,
    required this.priceInCurrency,
    required this.estimatedStorage,
  });

  factory PriceEstimate.zero() => PriceEstimate(
        credits: BigInt.from(0),
        priceInCurrency: 0,
        estimatedStorage: 0,
      );

  @override
  String toString() {
    return 'PriceEstimate{credits: $credits, priceInCurrency: $priceInCurrency, estimatedStorage: $estimatedStorage}';
  }

  @override
  List<Object?> get props => [
        credits,
        priceInCurrency,
        estimatedStorage,
      ];
}
