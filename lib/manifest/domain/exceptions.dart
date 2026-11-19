class ManifestCreationException implements Exception {
  final String message;
  final Object? error;

  ManifestCreationException(this.message, {this.error});

  @override
  String toString() {
    return 'ManifestCreationException: $message';
  }
}

/// The deployment's transaction was posted, and what came after failed: its
/// record could not be saved. It is paid for, so sending it again would pay
/// twice; [dataTxId] is what to look up.
class ManifestPostedException extends ManifestCreationException {
  final String dataTxId;

  ManifestPostedException(
    this.dataTxId, {
    super.error,
  }) : super('The deployment was posted but could not be saved.');
}
