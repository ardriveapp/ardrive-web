import 'package:permission_handler/permission_handler.dart';

class IOException implements Exception {}

class ActionCanceledException extends IOException {}

class FileSystemPermissionDeniedException extends IOException {
  FileSystemPermissionDeniedException(this.permissionsDenied);
  List<Permission> permissionsDenied;
}

class EntityPathException extends IOException {}

class UnsupportedPlatformException extends IOException {
  UnsupportedPlatformException([this.exception]);

  final String? exception;
}
