class MarkdownCreationException implements Exception {
  final String message;
  final Object? error;

  MarkdownCreationException(this.message, {this.error});
}
