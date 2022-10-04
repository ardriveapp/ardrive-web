import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:file_saver/file_saver.dart' as file_saver;
import 'package:mime/mime.dart' as mime;
import 'package:path/path.dart' as p;
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
    await _verifyStoragePermissions();

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
    await _verifyStoragePermissions();

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

    await _verifyStoragePermissions();

    final provider = _fileProviderFactory.fromSource(FileSource.fileSystem)
        as MultiFileProvider;

    return provider.getFolder();
  }

  Future<void> _verifyStoragePermissions() async {
    final status = await Permission.storage.request();

    if (status != PermissionStatus.granted) {
      throw FileSystemPermissionDeniedException([Permission.storage]);
    }
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

/// Opens the file picker dialog to select the folder to save
///
/// This implementation uses the `file_saver` package.
///
/// Throws an `FileSystemPermissionDeniedException` when user deny access to storage
class MobileSelectableFolderFileSaver implements FileSaver {
  @override
  Future<void> save(IOFile file) async {
    await requestPermissions();
    await verifyPermissions();

    String ext = getFileExtension(
      contentType: file.contentType,
      name: file.name,
      withExtensionDot: false,
    );

    await file_saver.FileSaver.instance.saveAs(
      p.basenameWithoutExtension(file.name),
      await file.readAsBytes(),
      ext,
      file.contentType,
    );

    return;
  }
}

/// Saves a file using the `dart:io` library.
/// It will save on `getDefaultMobileDownloadDir()`
class DartIOFileSaver implements FileSaver {
  @override
  Future<void> save(IOFile file) async {
    await requestPermissions();
    await verifyPermissions();

    String fileName = file.name;

    /// handles files without extension
    if (p.extension(file.name).isEmpty) {
      final fileExtension = mime.extensionFromMime(file.contentType);

      fileName += '.$fileExtension';
    }

    /// platform_specific_path/Downloads/
    final defaultDownloadDir = await getDefaultMobileDownloadDir();

    final newFile = File(defaultDownloadDir + fileName);

    await newFile.writeAsBytes(await file.readAsBytes());
  }
}

/// Defines the API for saving `IOFile` on Storage
abstract class FileSaver {
  factory FileSaver() {
    if (Platform.isAndroid || Platform.isIOS) {
      return MobileSelectableFolderFileSaver();
    }
    throw UnsupportedPlatformException(
        'The ${Platform.operatingSystem} platform is not supported');
  }

  Future<void> save(IOFile file);
}
