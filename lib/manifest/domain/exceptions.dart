class ManifestCreationException implements Exception {
  final String message;
  final Object? error;

  ManifestCreationException(this.message, {this.error});
}
