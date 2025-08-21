import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:mime/mime.dart' as mime;
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
    return _getDefaultAndroidDir();
  } else if (Platform.isIOS) {
    return _getDefaultIOSDir();
  } else {
    throw UnsupportedPlatformException(
      'getDefaultMobileDownloadDir only applies to mobile.',
    );
  }
}

Future<String> getDefaultAppDir() {
  return path_provider
      .getApplicationDocumentsDirectory()
      .then((value) => '${value.path}/');
}

/// Returns the file extension from the file `name`, when having, in other case the extension
/// will be provided by the `contentType`.
///
/// use `withExtensionDot` when want only the extension without the ` .`
///
/// For example: `application/pdf` => `pdf`
///
/// By default it will return with the ` .`
///
/// For example: `application/pdf` => `.pdf`
String getFileExtension({
  required String name,
  required String contentType,
  bool withExtensionDot = true,
}) {
  String ext = getFileExtensionFromFileName(fileName: name);

  if (ext.isNotEmpty) {
    if (withExtensionDot) {
      return ext;
    }

    return ext.replaceFirst('.', '');
  } else {
    ext = mime.extensionFromMime(contentType);

    if (withExtensionDot) {
      return '.$ext';
    }

    return ext;
  }
}

String getFileExtensionFromFileName({required String fileName}) {
  return path.extension(fileName);
}

String getFileTypeFromMime({required String contentType}) {
  return contentType.substring(contentType.lastIndexOf('/') + 1);
}

String getBasenameWithoutExtension({required String filePath}) {
  return path.basenameWithoutExtension(filePath);
}

Future<String> _getDefaultIOSDir() async {
  final iosDirectory = await path_provider.getApplicationDocumentsDirectory();
  final iosDownloadsDirectory = Directory('${iosDirectory.path}/Downloads/');

  if (!iosDownloadsDirectory.existsSync()) {
    iosDownloadsDirectory.createSync();
  }

  return iosDownloadsDirectory.path;
}

Future<String> _getDefaultAndroidDir() async {
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
      final directory = await path_provider.getApplicationDocumentsDirectory();
      return directory.path;
    }
  }
}

/// Searches for a nonexistent filename in the given [saveDir] and returns it.
/// If the file already exists, it will append a number to the filename in brackets.
/// Returns only the name of the file as a string.
Future<String> nonexistentFileName(
    String saveDir, String fileName, String? fileContentType) async {
  String potentialFileName;
  int counter = 0;
  File testFile;
  do {
    final baseWithoutExt = path.basenameWithoutExtension(fileName);

    if (counter == 0) {
      potentialFileName = baseWithoutExt;
    } else {
      potentialFileName = '$baseWithoutExt ($counter)';
    }

    var fileExtension = path.extension(fileName); // includes '.'
    if (fileExtension.isNotEmpty) {
      fileExtension = fileExtension.substring(1);
    } else if (fileContentType != null) {
      // For some reason `extensionFromMime` returns the (lowercase) input if it can't find
      // an extension. We only want to use the result if it is an actual extension.
      final fileExtensionOrMime =
          mime.extensionFromMime(fileContentType); // excludes '.'
      if (fileExtensionOrMime != fileContentType.toLowerCase()) {
        fileExtension = fileExtensionOrMime;
      }
    }

    if (fileExtension.isNotEmpty) {
      potentialFileName += '.$fileExtension';
    }

    testFile = File(saveDir + potentialFileName);

    counter++;

    // TODO: Throw an exception on arbitrarily large counter?
  } while (await testFile.exists());

  return potentialFileName;
}

Future<File> nonexistentFile(String saveDir, IOFile ioFile) async {
  final fileName =
      await nonexistentFileName(saveDir, ioFile.name, ioFile.contentType);
  return File(saveDir + fileName);
}
