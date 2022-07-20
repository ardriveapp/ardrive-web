import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_io/src/io_exception.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart' as file_saver;
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
    FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
        type: allowedExtensions == null ? FileType.any : FileType.custom);

    if (result != null) {
      return fileAdapter.fromFilePicker(result.files.first);
    }

    throw ActionCanceledException();
  }

  @override
  Future<List<IOFile>> pickFiles({List<String>? allowedExtensions}) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowedExtensions: allowedExtensions,
        allowMultiple: true,
        type: allowedExtensions == null ? FileType.any : FileType.custom);

    if (result != null) {
      return Future.wait(result.files.map((e) async {
        return fileAdapter.fromFilePicker(e);
      }).toList());
    }

    throw ActionCanceledException();
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

  @override
  Future<void> saveFile(IOFile file) async {
    try {
      await fileSaver.save(file);
    } catch (e) {
      rethrow;
    }
  }
}

/// Saves a file on default download location at **/storage/emulated/0/Download/**
///
/// throws a `EntityPathException` if the file name is invalid.
class AndroidDownloadsFileSaver implements FileSaver {
  @override
  Future<void> save(IOFile file) async {
    if (file.name.isEmpty) {
      throw EntityPathException();
    }

    Directory generalDownloadDir = Directory('/storage/emulated/0/Download/');

    await Permission.manageExternalStorage.request();
    await Permission.storage.request();

    if (await Permission.manageExternalStorage.isGranted &&
        await Permission.storage.isGranted) {
      await File(generalDownloadDir.path + file.name)
          .writeAsBytes(await file.readAsBytes());
      return;
    }

    throw FileSystemPermissionDeniedException();
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
          file.contentType,
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
