import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

import 'web/stub_web_io.dart' // Stub implementation
    if (dart.library.html) 'web/web_io.dart';

/// `gallery` device's gallery
/// `fileSystem` device's file system
///
/// on **Web** `gallery` is not supported.
enum FileSource { gallery, fileSystem, camera }

abstract class FileProvider {
  Future<IOFile> pickFile({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  });
}

/// Provides a `IOFolder`
abstract class FolderProvider {
  Future<IOFolder> getFolder();
}

/// Provides multiple `IOFiles` or an `IOFolder`
abstract class MultiFileProvider extends FileProvider with FolderProvider {
  Future<List<IOFile>> pickMultipleFiles({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  });
}

/// Pick a photo from the O.S's Camera
class CameraProvider implements FileProvider {
  CameraProvider(this._fileAdapter);

  final IOFileAdapter _fileAdapter;

  @override
  Future<IOFile> pickFile({
    List<String>? allowedExtensions,
    FileSource fileSource = FileSource.camera,
  }) async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera);

    if (file == null) {
      throw ActionCanceledException();
    }

    return _fileAdapter.fromXFile(file);
  }
}

/// MultiFileProvider implemented with file_picker package.
class FilePickerProvider implements MultiFileProvider {
  FilePickerProvider(
    this._fileAdapter,
    this._ioFolderAdapter,
  );

  final IOFileAdapter _fileAdapter;
  final IOFolderAdapter _ioFolderAdapter;

  @override
  Future<IOFile> pickFile({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  }) async {
    FilePickerResult result = await _pickFile(
        allowedExtensions: allowedExtensions, fileSource: fileSource);

    return _fileAdapter.fromFilePicker(result.files.first);
  }

  @override
  Future<List<IOFile>> pickMultipleFiles({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  }) async {
    FilePickerResult result = await _pickFile(
      allowedExtensions: allowedExtensions,
      allowMultiple: true,
      fileSource: fileSource,
    );

    for (var file in result.files) {
      print(file.path);
    }

    return Future.wait(
        result.files.map((file) => _fileAdapter.fromFilePicker(file)).toList());
  }

  Future<FilePickerResult> _pickFile({
    List<String>? allowedExtensions,
    bool allowMultiple = false,
    required FileSource fileSource,
  }) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowedExtensions: allowedExtensions,
        allowMultiple: allowMultiple,
        type: _getFileType(fileSource,
            allowedExtensions != null && allowedExtensions.isNotEmpty));

    if (result != null) {
      return result;
    }

    throw ActionCanceledException();
  }

  FileType _getFileType(
    FileSource fileSource,
    bool hasExtensionFilters,
  ) {
    switch (fileSource) {
      case FileSource.gallery:
        return FileType.media;
      case FileSource.fileSystem:
        if (hasExtensionFilters) {
          return FileType.custom;
        }
        return FileType.any;
      case FileSource.camera:
        throw FileSourceException(
            'Camera is not supported on FilePickerProvider');
    }
  }

  @override
  Future<IOFolder> getFolder() async {
    String? selectedDirectoryPath =
        await FilePicker.platform.getDirectoryPath();

    if (selectedDirectoryPath == null) {
      throw ActionCanceledException();
    }

    final selectedDirectory = Directory(selectedDirectoryPath);

    return _ioFolderAdapter.fromFileSystemDirectory(selectedDirectory);
  }
}

/// `fromSource` can return an instance of `FileProvider` or `MultiFileProvider`
///
class FileProviderFactory {
  /// `gallery` and `fileSystem` provides a `MultiFileProvider`
  /// In web, only `fileSystem` is allowed
  FileProvider fromSource(FileSource source) {
    if (kIsWeb) {
      if (source == FileSource.camera || source == FileSource.gallery) {
        throw UnsupportedPlatformException();
      }

      return WebFileSystemProvider(
        FolderPicker(),
        IOFileAdapter(),
        IOFolderAdapter(),
      );
    }

    switch (source) {
      case FileSource.gallery:
      case FileSource.fileSystem:
        return FilePickerProvider(
          IOFileAdapter(),
          IOFolderAdapter(),
        );
      case FileSource.camera:
        return CameraProvider(IOFileAdapter());
    }
  }
}

class IOCacheStorage {
  Future<String> saveEntityOnCacheDir(IOEntity entity) async {
    final cacheDir = await _getCacheDir();

    if (entity is IOFile) {
      debugPrint('saving file on local storage');

      final _file = File('${cacheDir.path}/${entity.name}');

      final readStream = File(entity.path).openRead();
      final writeStream = _file.openWrite();

      await for (List<int> chunk in readStream) {
        print(chunk.length);
        writeStream.write(chunk);
      }

      await writeStream.close();

      return _file.path;
    }

    if (entity is IOFolder) {
      return 'dir';
    }

    throw EntityPathException();
  }

  Future<IOFile> getFileFromStorage(String fileName) async {
    debugPrint('getting file from storage');

    final adapter = IOFileAdapter();

    final cacheDir = await _getCacheDir();

    final _file = File('${cacheDir.path}/$fileName');

    return adapter.fromFile(_file);
  }

  Future<void> freeLocalStorage() async {
    debugPrint('getting file from storage');

    final cacheDir = await _getCacheDir();

    cacheDir.deleteSync(recursive: true);
  }

  Future<Directory> _getCacheDir() async {
    final dir = await path_provider.getApplicationDocumentsDirectory();

    final cacheDir = Directory('${dir.path}/cache');

    if (!cacheDir.existsSync()) {
      await cacheDir.create();
    }

    return cacheDir;
  }
}
