import 'dart:io';

import 'package:ardrive_io/src/io_exception.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;

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

/// Gets the path to the default mobile downloads dir
///
/// Before usage it needs `Storage` permission
/// call:
/// 
/// ``` dart
/// await requestPermissions();
/// await verifyPermissions();
/// ```
Future<String> getDefaultMobileDownloadDir() async {
  if (Platform.isAndroid || Platform.isIOS) {
    final path = (await path_provider.getApplicationDocumentsDirectory()).path;
    final downloadDir = Directory(path + '/Downloads/');

    if (!downloadDir.existsSync()) {
      downloadDir.createSync();
    }

    return downloadDir.path;
  }

  throw UnsupportedPlatformException(
    'getDefaultMobileDownloadDir only applies to mobile.',
  );
}
