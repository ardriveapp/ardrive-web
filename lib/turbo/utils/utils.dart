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

/// Formats a storage amount in GiB to a human-readable string with dynamic units.
///
/// Automatically selects the most appropriate unit (KB, MB, GB, TB) based on size.
/// Examples:
///   - 0.0001 GiB -> "~102.4 KB"
///   - 0.5 GiB -> "~512.0 MB"
///   - 5.0 GiB -> "~5.0 GB"
///   - 1500 GiB -> "~1.5 TB"
String formatStorageWithDynamicUnit(double storageInGiB,
    {bool includeApprox = true}) {
  final prefix = includeApprox ? '~' : '';

  if (storageInGiB >= 1000) {
    return '$prefix${(storageInGiB / 1000).toStringAsFixed(1)} TB';
  }
  if (storageInGiB >= 1) {
    return '$prefix${storageInGiB.toStringAsFixed(1)} GB';
  }
  // Convert to MB (1 GiB = 1024 MiB)
  final storageMB = storageInGiB * 1024;
  if (storageMB >= 1) {
    return '$prefix${storageMB.toStringAsFixed(1)} MB';
  }
  // Convert to KB (1 MiB = 1024 KiB)
  final storageKB = storageMB * 1024;
  if (storageKB >= 1) {
    return '$prefix${storageKB.toStringAsFixed(1)} KB';
  }
  // Very small amount - show with more precision
  return '$prefix${storageKB.toStringAsFixed(2)} KB';
}
