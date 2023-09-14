String convertCreditsToLiteralString(BigInt credits) {
  final creditsAsAr = convertWinstonToAr(credits);
  final creditsString = creditsAsAr.toStringAsFixed(4);

  return creditsString;
}

double convertWinstonToAr(BigInt winston) {
  return winston / BigInt.from(1000000000000);
}
