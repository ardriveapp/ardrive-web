String convertWinstonToLiteralString(BigInt credits) {
  final creditsAsAr = convertWinstonToAr(credits);
  final creditsString = creditsAsAr.toStringAsFixed(4);

  return creditsString;
}

double convertWinstonToAr(BigInt winston) {
  return winston / BigInt.from(1000000000000);
}

/// Truncates a blockchain address for display.
///
/// Shows the first [prefix] and last [suffix] characters with ellipsis.
/// Example: "0x1234567890abcdef" -> "0x1234...cdef"
String truncateAddress(String address, {int prefix = 6, int suffix = 4}) {
  if (address.length <= prefix + suffix) return address;
  return '${address.substring(0, prefix)}...${address.substring(address.length - suffix)}';
}

/// Truncates a transaction ID for display.
///
/// Shows the first [prefix] and last [suffix] characters with ellipsis.
String truncateTxId(String txId, {int prefix = 8, int suffix = 8}) {
  if (txId.length <= prefix + suffix) return txId;
  return '${txId.substring(0, prefix)}...${txId.substring(txId.length - suffix)}';
}
