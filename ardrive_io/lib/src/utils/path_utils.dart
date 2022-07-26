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
