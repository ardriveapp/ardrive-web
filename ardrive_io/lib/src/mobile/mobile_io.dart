import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_io/src/io_exception.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart' as file_saver;
import 'package:mime/mime.dart' as mime;
import 'package:permission_handler/permission_handler.dart';

class MobileIO implements ArDriveIO {
  MobileIO(
      {required IOFileAdapter fileAdapter,
      required FileSaver fileSaver,
      required IOFolderAdapter folderAdapter})
      : _fileAdapter = fileAdapter,
        _fileSaver = fileSaver,
        _folderAdapter = folderAdapter;

  final FileSaver _fileSaver;
  final IOFileAdapter _fileAdapter;
  final IOFolderAdapter _folderAdapter;

  @override
  Future<IOFile> pickFile({List<String>? allowedExtensions}) async {
    FilePickerResult result =
        await _pickFile(allowedExtensions: allowedExtensions);

    return _fileAdapter.fromFilePicker(result.files.first);
  }

  @override
  Future<List<IOFile>> pickFiles({List<String>? allowedExtensions}) async {
    FilePickerResult result = await _pickFile(
        allowedExtensions: allowedExtensions, allowMultiple: true);

    return Future.wait(
        result.files.map((file) => _fileAdapter.fromFilePicker(file)).toList());
  }

  @override
  Future<IOFolder> pickFolder() async {
    String? selectedDirectoryPath =
        await FilePicker.platform.getDirectoryPath();

    if (selectedDirectoryPath == null) {
      throw ActionCanceledException();
    }

    final selectedDirectory = Directory(selectedDirectoryPath);

    final folder = _folderAdapter.fromFileSystemDirectory(selectedDirectory);

    return folder;
  }

  Future<FilePickerResult> _pickFile(
      {List<String>? allowedExtensions, bool allowMultiple = false}) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
      type: allowedExtensions == null ? FileType.any : FileType.custom,
    );

    if (result != null) {
      return result;
    }

    throw ActionCanceledException();
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
