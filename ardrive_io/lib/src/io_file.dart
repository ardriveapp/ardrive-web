import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// Base class for agnostic platform Files.
///
/// `contentType` is the file's MIME-TYPE
abstract class IOFile implements IOEntity {
  IOFile({required this.contentType});

  final String contentType;
  FutureOr<int> get length;
  Future<Uint8List> readAsBytes();
  Future<String> readAsString();

  static final IOFileAdapter _ioFileAdapter = IOFileAdapter();

  static Future<IOFile> fromData(Uint8List bytes,
          {required String name, required DateTime lastModifiedDate}) async =>
      _ioFileAdapter.fromData(
        bytes,
        name: name,
        lastModifiedDate: lastModifiedDate,
      );
}

/// Adapts the `IOFile` from different I/O sources.
///
/// Those are:
/// - file_picker: `PlatformFile`
/// - dart:io: `File`
/// - using an Uint8List to mount a file using its bytes in memory
class IOFileAdapter {
  Future<IOFile> fromFilePicker(
    PlatformFile result, {
    bool getFromCache = false,
  }) async {
    final resultFilePath = result.path;

    if (resultFilePath == null) {
      throw EntityPathException();
    }

    File file = File(resultFilePath);

    final lastModified = await file.lastModified();
    final fileName = result.name;
    final contentType = lookupMimeTypeWithDefaultType(file.path);

    final ioFile = _IOFile(
      file,
      name: fileName,
      path: resultFilePath,
      contentType: contentType,
      lastModifiedDate: lastModified,
    );

    if (getFromCache) {
      final cache = IOCacheStorage();

      final cachePath = await cache.saveEntityOnCacheDir(ioFile);

      debugPrint('Saving on cache: $cachePath');

      return _IOFile(
        File(cachePath),
        name: fileName,
        path: cachePath,
        contentType: contentType,
        lastModifiedDate: lastModified,
      );
    } else {
      debugPrint('Using default path from file picker');

      return ioFile;
    }
  }

  Future<IOFile> fromFile(File file) async {
    final lastModified = await file.lastModified();
    final contentType = lookupMimeTypeWithDefaultType(file.path);

    return _IOFile(
      file,
      name: getBasenameFromPath(file.path),
      path: file.path,
      contentType: contentType,
      lastModifiedDate: lastModified,
    );
  }

  Future<IOFile> fromXFile(XFile file) async {
    final lastModified = await file.lastModified();
    final contentType = lookupMimeTypeWithDefaultType(file.path);

    return _FromXFile(
      file,
      name: file.name,
      path: file.path,
      contentType: contentType,
      lastModifiedDate: lastModified,
    );
  }

  Future<IOFile> fromWebXFile(XFile xfile) async {
    final lastModified = await xfile.lastModified();
    final contentType = lookupMimeTypeWithDefaultType(xfile.path);

    return _FromXFile(
      xfile,
      name: xfile.name,
      path: xfile.path,
      contentType: contentType,
      lastModifiedDate: lastModified,
    );
  }

  /// Mounts a `_DataFile` with the given bytes.
  /// The path will always we a empty string since it only abstract the bytes in memory into a `_DataFile`
  Future<IOFile> fromData(Uint8List bytes,
      {required String name, required DateTime lastModifiedDate}) async {
    final contentType = lookupMimeTypeWithDefaultType(name);

    return _DataFile(
      bytes,
      contentType: contentType,
      path: '',
      lastModifiedDate: lastModifiedDate,
      name: name,
    );
  }
}

/// An implementation class that uses `dart:io` `File`
class _IOFile implements IOFile {
  _IOFile(
    File file, {
    required this.name,
    required this.lastModifiedDate,
    required this.path,
    required this.contentType,
  }) : _file = file;

  final File _file;

  @override
  String name;

  @override
  DateTime lastModifiedDate;

  @override
  String path;

  @override
  final String contentType;

  @override
  Future<Uint8List> readAsBytes() {
    return _file.readAsBytes();
  }

  @override
  Future<String> readAsString() {
    return _file.readAsString();
  }

  @override
  String toString() {
    return 'file name: $name\nfile path: $path\nlast modified date: ${lastModifiedDate.toIso8601String()}\nlength: $length';
  }

  @override
  int get length => _file.lengthSync();
}

/// `IOFile` implementation with the given `bytes`.
class _DataFile implements IOFile {
  _DataFile(
    this._bytes, {
    required this.contentType,
    required this.lastModifiedDate,
    required this.name,
    required this.path,
  });

  final Uint8List _bytes;

  @override
  final String contentType;

  @override
  final DateTime lastModifiedDate;

  @override
  final String name;

  @override
  final String path;

  @override
  Future<Uint8List> readAsBytes() async {
    return _bytes;
  }

  @override
  Future<String> readAsString() async {
    return utf8.decode(_bytes);
  }

  @override
  int get length => _bytes.length;

  @override
  String toString() {
    return 'file name: $name\nfile path: $path\nlast modified date: ${lastModifiedDate.toIso8601String()}\nlength: $length';
  }
}

class _FromXFile implements IOFile {
  _FromXFile(
    XFile file, {
    required this.name,
    required this.lastModifiedDate,
    required this.path,
    required this.contentType,
  }) : _file = file;

  final XFile _file;

  @override
  String name;

  @override
  DateTime lastModifiedDate;

  @override
  String path;

  @override
  final String contentType;

  @override
  Future<Uint8List> readAsBytes() {
    return _file.readAsBytes();
  }

  @override
  Future<String> readAsString() {
    return _file.readAsString();
  }

  @override
  String toString() {
    return 'file name: $name\nfile path: $path\nlast modified date: ${lastModifiedDate.toIso8601String()}\nlength: $length';
  }

  @override
  Future<int> get length => _file.length();
}
