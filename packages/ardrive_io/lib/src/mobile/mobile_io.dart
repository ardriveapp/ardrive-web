import 'dart:async';
import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_io/src/utils/completer.dart';
import 'package:file_saver/file_saver.dart' as file_saver;
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart' as mime;
import 'package:path/path.dart' as p;

class MobileIO implements ArDriveIO {
  MobileIO({
    required FileSaver fileSaver,
    required IOFolderAdapter folderAdapter,
    required FileProviderFactory fileProviderFactory,
  })  : _fileSaver = fileSaver,
        _fileProviderFactory = fileProviderFactory;

  final FileSaver _fileSaver;
  final FileProviderFactory _fileProviderFactory;

  @override
  Future<IOFile> pickFile({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  }) async {
    await verifyStoragePermission();

    final provider = _fileProviderFactory.fromSource(fileSource);

    return provider.pickFile(
      fileSource: fileSource,
      allowedExtensions: allowedExtensions,
    );
  }

  @override
  Future<List<IOFile>> pickFiles({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  }) async {
    await verifyStoragePermission();

    final provider =
        _fileProviderFactory.fromSource(fileSource) as MultiFileProvider;

    final files = await provider.pickMultipleFiles(
      fileSource: fileSource,
      allowedExtensions: allowedExtensions,
    );

    return files;
  }

  @override
  Future<IOFolder> pickFolder() async {
    if (Platform.isAndroid) {
      await requestPermissions();
    }

    await verifyStoragePermission();

    final provider = _fileProviderFactory.fromSource(FileSource.fileSystem)
        as MultiFileProvider;

    return provider.getFolder();
  }

  @override
  Future<void> saveFile(IOFile file, [bool saveOnAppDirectory = false]) async {
    try {
      await _fileSaver.save(file, saveOnAppDirectory: saveOnAppDirectory);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Stream<SaveStatus> saveFileStream(
      IOFile file, Completer<bool> finalize) async* {
    try {
      yield* _fileSaver.saveStream(file, finalize);
    } catch (e) {
      rethrow;
    }
  }
}

/// Opens the file picker dialog to select the folder to save
///
/// This implementation uses the `file_saver` package.
///
/// Throws an `FileSystemPermissionDeniedException` when user deny access to storage
///
/// `saveOnAppDirectory` is not supported on this implementation
class MobileSelectableFolderFileSaver implements FileSaver {
  final DartIOFileSaver _dartIOFileSaver;

  MobileSelectableFolderFileSaver({DartIOFileSaver? dartIOFileSaver})
      : _dartIOFileSaver = dartIOFileSaver ?? DartIOFileSaver();

  @override
  Future<void> save(IOFile file, {bool saveOnAppDirectory = false}) async {
    await requestPermissions();
    await verifyPermissions();

    if (saveOnAppDirectory) {
      await _dartIOFileSaver.save(file, saveOnAppDirectory: saveOnAppDirectory);
      return;
    }

    await file_saver.FileSaver.instance.saveAs(
      name: file.name,
      bytes: await file.readAsBytes(),
      mimeType: file.contentType,
    );

    return;
  }

  @override
  Stream<SaveStatus> saveStream(IOFile file, Completer<bool> finalize) {
    // file_saver doesn't seem to support support saving streams
    throw UnimplementedError();
  }
}

/// Saves a file using the `dart:io` library.
/// It will save on `getDefaultMobileDownloadDir()`
class DartIOFileSaver implements FileSaver {
  @override
  Future<void> save(IOFile file, {bool saveOnAppDirectory = false}) async {
    await requestPermissions();
    await verifyPermissions();

    String fileName = file.name;

    /// handles files without extension
    if (p.extension(file.name).isEmpty) {
      final fileExtension = mime.extensionFromMime(file.contentType);

      fileName += '.$fileExtension';
    }

    if (saveOnAppDirectory) {
      await _saveOnAppDir(file, fileName);
      return;
    }

    await _saveOnDownloadsDir(file, fileName);
  }

  Future<void> _saveOnDownloadsDir(IOFile file, String fileName) async {
    /// platform_specific_path/Downloads/
    final defaultDownloadDir = await getDefaultMobileDownloadDir();

    final newFile = await nonexistentFile(defaultDownloadDir, file);

    await newFile.writeAsBytes(await file.readAsBytes());
  }

  Future<void> _saveOnAppDir(IOFile file, String fileName) async {
    final appDir = await getDefaultAppDir();

    final newFile = File(appDir + fileName);

    await newFile.writeAsBytes(await file.readAsBytes());
  }

  @override
  Stream<SaveStatus> saveStream(IOFile file, Completer<bool> finalize) async* {
    var bytesSaved = 0;
    final totalBytes = await file.length;
    yield SaveStatus(
      bytesSaved: bytesSaved,
      totalBytes: totalBytes,
    );

    try {
      await requestPermissions();
      await verifyPermissions();

      /// platform_specific_path/Downloads/
      final defaultDownloadDir = await getDefaultMobileDownloadDir();

      final newFile = await nonexistentFile(defaultDownloadDir, file);

      final sink = newFile.openWrite();

      // NOTE: This is an alternative to `addStream` with lower level control
      const flushThresholdBytes = 50 * 1024 * 1024; // 50 MiB
      var unflushedDataBytes = 0;
      await for (final chunk in file.openReadStream()) {
        if (await completerMaybe(finalize) == false) break;

        sink.add(chunk);
        unflushedDataBytes += chunk.length;
        if (unflushedDataBytes > flushThresholdBytes) {
          await sink.flush();
          unflushedDataBytes = 0;
        }

        bytesSaved += chunk.length;
        yield SaveStatus(
          bytesSaved: bytesSaved,
          totalBytes: totalBytes,
        );
      }
      await sink.flush();
      await sink.close();

      final finalizeResult = await finalize.future;
      if (!finalizeResult) {
        debugPrint('Cancelling saveStream...');
        await newFile.delete();
      }

      yield SaveStatus(
        bytesSaved: bytesSaved,
        totalBytes: totalBytes,
        saveResult: finalizeResult,
      );
    } catch (e) {
      yield SaveStatus(
        bytesSaved: bytesSaved,
        totalBytes: totalBytes,
        saveResult: false,
      );
    }
  }
}

/// Defines the API for saving `IOFile` on Storage
abstract class FileSaver {
  factory FileSaver() {
    if (Platform.isAndroid || Platform.isIOS) {
      return DartIOFileSaver();
    }
    throw UnsupportedPlatformException(
        'The ${Platform.operatingSystem} platform is not supported');
  }

  Future<void> save(IOFile file, {bool saveOnAppDirectory = false});

  Stream<SaveStatus> saveStream(IOFile file, Completer<bool> finalize);
}
