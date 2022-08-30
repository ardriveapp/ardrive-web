import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_io/src/io_exception.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

abstract class FileProvider {
  Future<IOFile> pickFile({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  });
}

abstract class MultiFileProvider extends FileProvider {
  Future<List<IOFile>> pickMultipleFiles({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  });
}

class FileProviderFactory {
  FileProvider fromSource(FileSource source) {
    switch (source) {
      case FileSource.gallery:
      case FileSource.fileSystem:
        return FilePickerProvider(IOFileAdapter());
      case FileSource.camera:
        return CameraProvider(IOFileAdapter());
    }
  }
}

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

class FilePickerProvider implements MultiFileProvider {
  FilePickerProvider(this._fileAdapter);

  final IOFileAdapter _fileAdapter;

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
}

/// `gallery` device's gallery
/// `fileSystem` device's file system
///
/// on **Web** `gallery` is not supported.
enum FileSource { gallery, fileSystem, camera }
