// Shared types and exceptions for Turbo SDK interop

/// Exception thrown when the Turbo SDK is not loaded.
class TurboSDKNotLoadedException implements Exception {
  final String message;

  TurboSDKNotLoadedException(this.message);

  @override
  String toString() => 'TurboSDKNotLoadedException: $message';
}

class TurboSDKException implements Exception {
  final String message;
  final Object? originalError;

  TurboSDKException(this.message, [this.originalError]);

  @override
  String toString() => 'TurboSDKException: $message';
}
