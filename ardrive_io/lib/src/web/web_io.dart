import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:typed_data';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_io/src/io_exception.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:file_selector/file_selector.dart';

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
    final savePath = await getSavePath();
    if (savePath == null) {
      throw EntityPathException();
    }

    file_selector.XFile(file.path).saveTo(savePath);
  }
}

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

      _folderController.add(files
          .map((e) => WebFile(e,
              name: e.name,
              lastModifiedDate: e.lastModifiedDate,
              path: e.relativePath!,
              contentType: lookupMimeTypeWithDefaultType(e.relativePath!)))
          .toList());

      /// Closes to finish the stream with all files
      _folderController.close();

      folderInput.removeAttribute('webkitdirectory');
      folderInput.removeEventListener('webkitdirectory', (event) => null);
      folderInput.remove();
      return;
    });
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
    if (_bytes == null) {
      final reader = FileReader();
      reader.readAsArrayBuffer(_file);
      await reader.onLoad.first;
      return reader.result as Uint8List;
    }

    return _bytes!;
  }

  @override
  Future<String> readAsString() async {
    return utf8.decode(await readAsBytes());
  }

  @override
  FutureOr<int> get length => _length();

  Future<int> _length() async {
    final bytes = await readAsBytes();

    return bytes.length;
  }

  @override
  String toString() {
    return 'file name: $name\nfile path: $path\nlast modified date: ${lastModifiedDate.toIso8601String()}\nlength: $length';
  }
}
