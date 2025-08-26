import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

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
abstract class MultiFileProvider extends FileProvider
    implements FolderProvider {
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
    final status = await Permission.camera.request();

    if (status != PermissionStatus.granted) {
      throw FileSystemPermissionDeniedException([Permission.camera]);
    }

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

    return Future.wait(result.files
        .map((file) => _fileAdapter.fromFilePicker(
              file,
              getFromCache: Platform.isIOS,
            ))
        .toList());
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

    return secureScopedAction<IOFolder>(
      (secureDir) => _ioFolderAdapter.fromFileSystemDirectory(secureDir),
      selectedDirectory,
    );
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
