import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_io/src/io_exception.dart';
import 'package:file_saver/file_saver.dart' as file_saver;
import 'package:mime/mime.dart' as mime;
import 'package:permission_handler/permission_handler.dart';

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
    final provider =
        _fileProviderFactory.fromSource(fileSource) as MultiFileProvider;

    return provider.pickMultipleFiles(
      fileSource: fileSource,
      allowedExtensions: allowedExtensions,
    );
  }

  @override
  Future<IOFolder> pickFolder() async {
    final provider = _fileProviderFactory.fromSource(FileSource.fileSystem)
        as MultiFileProvider;

    return provider.getFolder();
  }

  @override
  Future<void> saveFile(IOFile file) async {
    try {
      await _fileSaver.save(file);
    } catch (e) {
      rethrow;
    }
  }
}

/// Opens the file picker dialog to select the folder to save.
///
/// It uses the `file_saver` package.
class AndroidSelectableFolderFileSaver implements FileSaver {
  @override
  Future<void> save(IOFile file) async {
    await _requestPermissions();
    await _verifyPermissions();

    await file_saver.FileSaver.instance.saveAs(
        file.name,
        await file.readAsBytes(),
        mime.extensionFromMime(file.contentType),
        getMimeTypeFromString(file.contentType));

    return;
  }

  Future<void> _verifyPermissions() async {
    if (await Permission.storage.isGranted) {
      return;
    }

    throw FileSystemPermissionDeniedException([Permission.storage]);
  }

  Future<void> _requestPermissions() async {
    await Permission.storage.request();
  }
}

class IOSFileSaver implements FileSaver {
  @override
  Future<void> save(IOFile file) async {
    throw UnimplementedError();
  }
}

abstract class FileSaver {
  factory FileSaver() {
    if (Platform.isAndroid) {
      return AndroidSelectableFolderFileSaver();
    }
    if (Platform.isIOS) {
      return IOSFileSaver();
    }
    throw UnsupportedPlatformException(
        'The ${Platform.operatingSystem} platform is not supported');
  }

  Future<void> save(IOFile file);
}
