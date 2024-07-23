class ArweaveServiceException implements Exception {
  final String message;

  ArweaveServiceException(this.message);

  @override
  String toString() {
    return 'ArweaveServiceException: $message';
  }
}
