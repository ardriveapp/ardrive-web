import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ardrive_io/src/io_entity.dart';
import 'package:ardrive_io/src/io_exception.dart';
import 'package:ardrive_io/src/utils/file_path_utils.dart';
import 'package:ardrive_io/src/utils/mime_type_utils.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';

abstract class IOFile implements IOEntity {
  IOFile({required this.fileExtension, required this.contentType});

  Future<Uint8List> readAsBytes();
  Future<String> readAsString();
  final String contentType;
  final String fileExtension;
}

class IOFileAdapter {
  Future<IOFile> fromFilePicker(PlatformFile result) async {
    final resultFilePath = result.path;

    if (resultFilePath == null) {
      throw EntityPathException();
    }

    File file = File(resultFilePath);

    final lastModified = await file.lastModified();
    final fileName = result.name;
    final contentType = lookupMimeTypeWithDefaultType(file.path);

    return _CommonFile(
        file: file,
        name: fileName,
        fileExtension: getExtensionFromPath(resultFilePath),
        path: file.path,
        contentType: contentType,
        lastModifiedDate: lastModified);
  }

  Future<IOFile> fromFile(File file) async {
    /// TODO(@thiagocarvalhodev): Verify if we need an method for that to decouple it from xFILE
    final xfile = XFile(file.path);
    final lastModified = await file.lastModified();
    final contentType = lookupMimeTypeWithDefaultType(file.path);

    return _CommonFile(
        file: file,
        name: xfile.name,
        fileExtension: getExtensionFromPath(file.path),
        path: file.path,
        contentType: contentType,
        lastModifiedDate: lastModified);
  }

  /// Mounts a `IOFile` with the given information
  /// `path` is optional since it will be stored in memory
  Future<IOFile> fromData(Uint8List bytes,
      {required String name,
      String? path,
      required String contentType,
      required DateTime lastModified,
      required String fileExtension}) async {
    return _DataFile(bytes,
        contentType: contentType,
        fileExtension: fileExtension,
        path: path ?? '',
        lastModifiedDate: DateTime.now(),
        name: name);
  }
}

class _CommonFile implements IOFile {
  _CommonFile(
      {required this.file,
      required this.name,
      required this.lastModifiedDate,
      required this.path,
      required this.fileExtension,
      required this.contentType});

  @override
  Future<Uint8List> readAsBytes() {
    return file.readAsBytes();
  }

  @override
  Future<String> readAsString() {
    return file.readAsString();
  }

  final File file;

  @override
  String name;

  @override
  DateTime lastModifiedDate;

  @override
  String path;

  @override
  String fileExtension;

  @override
  String toString() {
    return 'file name: $name\nfile extension: $fileExtension\nfile path: $path\nlast modified date: ${lastModifiedDate.toIso8601String()}';
  }

  @override
  final String contentType;
}

/// `IOFile` implementation with the given `bytes`.
class _DataFile implements IOFile {
  _DataFile(this.bytes,
      {required this.contentType,
      required this.fileExtension,
      required this.lastModifiedDate,
      required this.name,
      required this.path});

  final Uint8List bytes;

  @override
  final String contentType;
  @override
  final String fileExtension;

  @override
  final DateTime lastModifiedDate;

  @override
  final String name;

  @override
  final String path;

  @override
  Future<Uint8List> readAsBytes() async {
    return bytes;
  }

  @override
  Future<String> readAsString() async {
    return utf8.decode(bytes);
  }
}
