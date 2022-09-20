import 'dart:io';

import 'package:ardrive_io/src/io_exception.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:permission_handler/permission_handler.dart';

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

  return path.dirname(entityPath);
}

Future<String> getDefaultDownloadDir() async {
  await Permission.storage.request();

  final path = (await path_provider.getApplicationDocumentsDirectory()).path;
  final downloadDir = Directory(path + '/Downloads');

  if (!downloadDir.existsSync()) {
    downloadDir.createSync();
  }

  return downloadDir.path;
}
