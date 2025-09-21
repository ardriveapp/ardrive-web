import 'dart:async';

import 'package:ardrive_io/ardrive_io.dart';

class WebIO implements ArDriveIO {
  WebIO({
    required FileProviderFactory fileProviderFactory,
  });

  @override
  Future<IOFile> pickFile({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<IOFile>> pickFiles({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<IOFolder> pickFolder() {
    throw UnimplementedError();
  }

  @override
  Future<void> saveFile(IOFile file) {
    throw UnimplementedError();
  }

  @override
  Stream<SaveStatus> saveFileStream(IOFile file, Completer<bool> finalize) {
    throw UnimplementedError();
  }
}

class FolderPicker {
  Future pickFolderFiles(Function(List<IOFile> files) getFilesCallback) async {
    throw UnimplementedError();
  }
}

class WebFileSystemProvider implements MultiFileProvider {
  WebFileSystemProvider(
    FolderPicker folderPicker,
    IOFileAdapter ioFileAdapter,
    IOFolderAdapter ioFolderAdapter,
  );

  @override
  Future<IOFolder> getFolder() {
    throw UnimplementedError();
  }

  @override
  Future<IOFile> pickFile(
      {List<String>? allowedExtensions, required FileSource fileSource}) {
    throw UnimplementedError();
  }

  @override
  Future<List<IOFile>> pickMultipleFiles(
      {List<String>? allowedExtensions, required FileSource fileSource}) {
    throw UnimplementedError();
  }
}
