import 'package:ardrive_io/src/io_exception.dart';
import 'package:path/path.dart' as path;

/// Returns the folder name to the given path
///
/// Accepts a non empty String
String getFolderNameFromPath(String folderPath) {
  if (folderPath.isEmpty) {
    throw EntityPathException();
  }

  return path.basename(folderPath);
}

/// Returns the Gets the part of [entityPath] before the last separator.
/// Accepts a non empty String
String getDirname(String entityPath) {
  if (entityPath.isEmpty) {
    throw EntityPathException();
  }

  return path.dirname(entityPath);
}
