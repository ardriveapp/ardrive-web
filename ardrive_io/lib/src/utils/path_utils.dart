import 'package:ardrive_io/src/io_exception.dart';
import 'package:path/path.dart' as path;

/// Returns the folder name to the given path
///
/// Accepts a non empty String
String getBasenameFromPath(String entityPath) {
  if (entityPath.isEmpty) {
    throw EntityPathException();
  }

  return path.basename(entityPath);
}

/// Returns the Gets the part of [entityPath] before the last separator.
/// Accepts a non empty String
String getDirname(String entityPath) {
  if (entityPath.isEmpty) {
    throw EntityPathException();
  }

  final dirname = path.dirname(entityPath);
  print('The dirname of $entityPath: $dirname');
  return dirname;
}
