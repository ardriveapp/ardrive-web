import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_io/src/io_exception.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

class FileProviderFactory {
  FileProvider fromSource(FileSource source) {
    switch (source) {
      case FileSource.gallery:
      case FileSource.fileSystem:
        return FilePickerProvider(IOFileAdapter());
      case FileSource.camera:
        return CameraProvider();
    }
  }
}

abstract class FileProvider {
  Future<IOFile> pickFile(
      {List<String>? allowedExtensions, required FileSource fileSource});
}

class CameraProvider implements FileProvider {
    CameraProvider(this._fileAdapter);
    
  final IOFileAdapter _fileAdapter;


  @override
  Future<IOFile> pickFile(
      {List<String>? allowedExtensions, required FileSource fileSource}) async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera);


    return _fileAdapter.from
  }
}

abstract class MultiFileProvider extends FileProvider {
  Future<List<IOFile>> pickMultipleFiles(
      {List<String>? allowedExtensions, required FileSource fileSource});
}

class FilePickerProvider implements MultiFileProvider {
  FilePickerProvider(this._fileAdapter);

  final IOFileAdapter _fileAdapter;

  @override
  Future<IOFile> pickFile(
      {List<String>? allowedExtensions, required FileSource fileSource}) async {
    FilePickerResult result = await _pickFile(
        allowedExtensions: allowedExtensions, fileSource: fileSource);

    return _fileAdapter.fromFilePicker(result.files.first);
  }

  @override
  Future<List<IOFile>> pickMultipleFiles(
      {List<String>? allowedExtensions, required FileSource fileSource}) async {
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
        return FileType.any;
    }
  }
}

/// `gallery` device's gallery
/// `fileSystem` device's file system
///
/// on **Web** `gallery` is not supported.
enum FileSource { gallery, fileSystem, camera }
