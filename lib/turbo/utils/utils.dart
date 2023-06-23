String convertCreditsToLiteralString(BigInt credits) {
  return convertWinstonToAR(credits).toStringAsFixed(4);
}

double convertWinstonToAR(BigInt winston) {
  return winston / BigInt.from(1000000000000);
}
