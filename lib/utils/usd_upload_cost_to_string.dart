String usdUploadCostToString(double usdUploadCost) {
  return usdUploadCost >= 0.01
      ? ' (~${usdUploadCost.toStringAsFixed(2)} USD)'
      : ' (< 0.01 USD)';
}
