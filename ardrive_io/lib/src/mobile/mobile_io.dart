import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_io/src/io_exception.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart' as file_saver;
import 'package:mime/mime.dart' as mime;
import 'package:permission_handler/permission_handler.dart';

class MobileIO implements ArDriveIO {
  MobileIO(
      {required this.fileAdapter,
      required this.fileSaver,
      required this.folderAdapter});

  final FileSaver fileSaver;
  final IOFileAdapter fileAdapter;
  final IOFolderAdapter folderAdapter;

  @override
  Future<IOFile> pickFile({List<String>? allowedExtensions}) async {
    FilePickerResult result =
        await _pickFile(allowedExtensions: allowedExtensions);

    return fileAdapter.fromFilePicker(result.files.first);
  }

  @override
  Future<List<IOFile>> pickFiles({List<String>? allowedExtensions}) async {
    FilePickerResult result = await _pickFile(
        allowedExtensions: allowedExtensions, allowMultiple: true);

    return Future.wait(result.files.map((e) async {
      return fileAdapter.fromFilePicker(e);
    }).toList());
  }

  @override
  Future<IOFolder> pickFolder() async {
    String? selectedDirectoryPath =
        await FilePicker.platform.getDirectoryPath();

    if (selectedDirectoryPath == null) {
      throw ActionCanceledException();
    }

    final selectedDirectory = Directory(selectedDirectoryPath);

    final folder = folderAdapter.fromFileSystemDirectory(selectedDirectory);

    return folder;
  }

  Future<FilePickerResult> _pickFile(
      {List<String>? allowedExtensions, bool allowMultiple = false}) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowedExtensions: allowedExtensions,
        allowMultiple: allowMultiple,
        type: allowedExtensions == null ? FileType.any : FileType.custom);

    if (result != null) {
      return result;
    }

    throw ActionCanceledException();
  }

  @override
  Future<void> saveFile(IOFile file) async {
    try {
      await fileSaver.save(file);
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
    await Permission.manageExternalStorage.request();
    await Permission.storage.request();

    if (await Permission.manageExternalStorage.isGranted &&
        await Permission.storage.isGranted) {
      await file_saver.FileSaver.instance.saveAs(
          file.name,
          await file.readAsBytes(),

          /// TODO(@thiagocarvalhodev): implement a function to get the extension

          mime.extensionFromMime(file.contentType),
          getMimeTypeFromString(file.contentType));

      return;
    }

    throw FileSystemPermissionDeniedException();
  }
}

class IOSFileSaver implements FileSaver {
  @override
  Future<void> save(IOFile file) async {
    /// TODO: implement save
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
