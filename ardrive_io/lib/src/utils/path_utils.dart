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
