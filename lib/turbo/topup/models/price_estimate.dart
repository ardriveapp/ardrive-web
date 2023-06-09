class PriceEstimate {
  final BigInt credits;
  final int priceInCurrency;
  final double estimatedStorage;

  PriceEstimate({
    required this.credits,
    required this.priceInCurrency,
    required this.estimatedStorage,
  });

  @override
  String toString() {
    return 'PriceEstimate{credits: $credits, priceInCurrency: $priceInCurrency, estimatedStorage: $estimatedStorage}';
  }
}
