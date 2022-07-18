class IOException implements Exception {}

class ActionCanceledException extends IOException {}

class FileSystemPermissionDeniedException extends IOException {}

class EntityPathException extends IOException {}

class UnsupportedPlatformException extends IOException {
  UnsupportedPlatformException([this.exception]);

  final String? exception;
}
