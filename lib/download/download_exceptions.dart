/// All gateways returned 404 for this transaction.
class DownloadFileNotFoundException implements Exception {
  final String txId;
  const DownloadFileNotFoundException(this.txId);

  @override
  String toString() => 'File not found on any gateway: $txId';
}

/// All gateways failed with network/timeout/5xx errors.
class DownloadNetworkException implements Exception {
  final String txId;
  final String? lastError;
  const DownloadNetworkException(this.txId, [this.lastError]);

  @override
  String toString() =>
      'All gateways failed for download $txId: ${lastError ?? 'unknown'}';
}

/// Rate-limited by gateway(s) and all fallbacks also failed.
class DownloadRateLimitException implements Exception {
  final String txId;
  const DownloadRateLimitException(this.txId);

  @override
  String toString() => 'Rate limited on all gateways for download: $txId';
}

/// Download stream started but no bytes received within timeout.
class DownloadStalledException implements Exception {
  final String txId;
  final Duration timeout;
  const DownloadStalledException(this.txId, this.timeout);

  @override
  String toString() =>
      'Download stalled for $txId: no data for ${timeout.inSeconds}s';
}
