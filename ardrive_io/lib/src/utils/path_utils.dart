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
  if (Platform.isAndroid) {
    final Directory defaultAndroidDownloadDir =
        Directory('/storage/emulated/0/Download/');

    if (await Permission.manageExternalStorage.isGranted &&
        await defaultAndroidDownloadDir.exists()) {
      return defaultAndroidDownloadDir.path;
    } else {
      final externalDir = await path_provider.getExternalStorageDirectory();

      if (externalDir != null) {
        return externalDir.path;
      } else {
        final directory =
            await path_provider.getApplicationDocumentsDirectory();
        return directory.path;
      }
    }
  } else if (Platform.isIOS) {
    final iosDirectory = await path_provider.getApplicationDocumentsDirectory();
    final iosDownloadsDirectory = Directory(iosDirectory.path + '/Downloads/');

    if (!iosDownloadsDirectory.existsSync()) {
      iosDownloadsDirectory.createSync();
    }

    return iosDownloadsDirectory.path;
  } else {
    throw UnsupportedPlatformException(
      'getDefaultMobileDownloadDir only applies to mobile.',
    );
  }
}
