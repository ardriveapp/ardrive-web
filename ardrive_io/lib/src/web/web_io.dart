import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:typed_data';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_io/src/io_exception.dart';
import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:mime/mime.dart' as mime;

/// Web implementation to use `ArDriveIO` API
///
class WebIO implements ArDriveIO {
  WebIO(
      {required IOFileAdapter fileAdapter,
      required FolderPicker folderPicker,
      required IOFolderAdapter folderAdapter})
      : _fileAdapter = fileAdapter,
        _folderAdapter = folderAdapter,
        _folderPicker = folderPicker;

  final IOFileAdapter _fileAdapter;
  final IOFolderAdapter _folderAdapter;
  final FolderPicker _folderPicker;

  @override
  Future<IOFile> pickFile({List<String>? allowedExtensions}) async {
    final file = await file_selector.openFile(acceptedTypeGroups: [
      file_selector.XTypeGroup(extensions: allowedExtensions)
    ]);

    if (file == null) {
      throw ActionCanceledException();
    }

    return _fileAdapter.fromWebXFile(file);
  }

  @override
  Future<List<IOFile>> pickFiles({List<String>? allowedExtensions}) async {
    final xFiles = await file_selector.openFiles(acceptedTypeGroups: [
      file_selector.XTypeGroup(extensions: allowedExtensions)
    ]);

    if (xFiles.isEmpty) {
      throw ActionCanceledException();
    }

    return Future.wait(
        xFiles.map((xfile) => _fileAdapter.fromWebXFile(xfile)).toList());
  }

  @override
  Future<IOFolder> pickFolder() async {
    final files = <IOFile>[];

    late Stream<List<IOFile>> folderStream;

    _folderPicker.pickFolderFiles((stream) => folderStream = stream);

    await for (var file in folderStream) {
      files.addAll(file);
    }

    return _folderAdapter.fromIOFiles(files);
  }

  @override
  Future<void> saveFile(IOFile file) async {
    await FileSaver.instance.saveFile(file.name, await file.readAsBytes(),
        mime.extensionFromMime(file.contentType),
        mimeType: getMimeTypeFromString(file.contentType));
  }
}

/// Pass a stream to the `getFiles` callback to stream files
/// When the file picker window is closed it will return a list of `IOFile`
class FolderPicker {
  Future<void> pickFolderFiles(
      Function(Stream<List<IOFile>> stream) getFiles) async {
    StreamController<List<IOFile>> _folderController =
        StreamController<List<IOFile>>();

    /// Set the stream to get the files
    getFiles(_folderController.stream);

    final folderInput = FileUploadInputElement();

    folderInput.setAttribute('webkitdirectory', true);

    folderInput.click();

    folderInput.onChange.listen((e) async {
      // read file content as dataURL
      final files = folderInput.files;

      if (files == null) {
        throw ActionCanceledException();
      }

      /// To avoid the `IOFileAdapter` imports dart:html, this file will be mounted
      /// here.
      _folderController.add(files.map((e) => _mountFile(e)).toList());

      /// Closes to finish the stream with all files
      _folderController.close();
      folderInput.removeAttribute('webkitdirectory');
      folderInput.remove();
    });
  }

  WebFile _mountFile(File e) {
    final path = e.relativePath;
    if (path == null) {
      throw EntityPathException();
    }

    /// Needs on safari. Some files doesn't have the lastModified and an exception
    /// is thrown
    DateTime lastModifiedDate;
    try {
      lastModifiedDate = e.lastModifiedDate;
    } catch (e) {
      lastModifiedDate = DateTime.now();
    }

    return WebFile(e,
        name: e.name,
        lastModifiedDate: lastModifiedDate,
        path: path,
        contentType: lookupMimeTypeWithDefaultType(path));
  }
}

class WebFile implements IOFile {
  WebFile(
    File file, {
    required this.name,
    required this.lastModifiedDate,
    required this.path,
    required this.contentType,
  }) : _file = file;

  final File _file;

  Uint8List? _bytes;

  @override
  String name;

  @override
  DateTime lastModifiedDate;

  @override
  String path;

  @override
  final String contentType;

  @override
  Future<Uint8List> readAsBytes() async {
    final bytes = _bytes;
    if (bytes == null) {
      final reader = FileReader();
      reader.readAsArrayBuffer(_file);
      await reader.onLoad.first;
      return reader.result as Uint8List;
    }

    return bytes;
  }

  @override
  Future<String> readAsString() async {
    return utf8.decode(await readAsBytes());
  }

  @override
  FutureOr<int> get length async => (await readAsBytes()).length;

  @override
  String toString() {
    return 'file name: $name\nfile path: $path\nlast modified date: ${lastModifiedDate.toIso8601String()}\nlength: $length';
  }
}
