import 'package:ardrive_io/src/io_exception.dart';

String getExtensionFromPath(String path) {
  if (path.isEmpty) {
    throw EntityPathException();
  }
  return path.split('/').last.split('.').last;
}

String getFolderNameFromPath(String path) {
  if (path.isEmpty) {
    throw EntityPathException();
  }
  return path.split('/').last;
}
