import 'dart:async';

import 'package:ardrive_io/ardrive_io.dart';

class ArDriveIOIntegrationTest implements ArDriveIO {
  List<IOFile>? _pickFileResult;
  IOFile? _pickFileResultSingle;

  void setPickFileResult(IOFile file) {
    _pickFileResultSingle = file;
  }

  void setPickFileResultList(List<IOFile> files) {
    _pickFileResult = files;
  }

  @override
  Future<IOFile> pickFile(
      {List<String>? allowedExtensions, required FileSource fileSource}) {
    return Future.value(_pickFileResultSingle!);
  }

  @override
  Future<List<IOFile>> pickFiles(
      {List<String>? allowedExtensions, required FileSource fileSource}) {
    return Future.value(_pickFileResult!);
  }

  @override
  Future<IOFolder> pickFolder() {
    throw UnimplementedError();
  }

  @override
  Future<void> saveFile(IOFile file) {
    return Future.value();
  }

  @override
  Stream<SaveStatus> saveFileStream(IOFile file, Completer<bool> finalize) {
    return Stream.value(SaveStatus(
      bytesSaved: 0,
      totalBytes: 0,
    ));
  }
}
//
