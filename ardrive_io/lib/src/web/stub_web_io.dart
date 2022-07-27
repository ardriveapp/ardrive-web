import 'dart:async';

import 'package:ardrive_io/ardrive_io.dart';

class WebIO implements ArDriveIO {
  WebIO(
      {required IOFileAdapter fileAdapter,
      required FolderPicker folderPicker,
      required IOFolderAdapter folderAdapter});

  @override
  Future<IOFile> pickFile({List<String>? allowedExtensions}) {
    // TODO: implement pickFile
    throw UnimplementedError();
  }

  @override
  Future<List<IOFile>> pickFiles({List<String>? allowedExtensions}) {
    // TODO: implement pickFiles
    throw UnimplementedError();
  }

  @override
  Future<IOFolder> pickFolder() {
    // TODO: implement pickFolder
    throw UnimplementedError();
  }

  @override
  Future<void> saveFile(IOFile file) {
    // TODO: implement saveFile
    throw UnimplementedError();
  }
}

class FolderPicker {
  Future pickFolderFiles(Function(List<IOFile> files) getFilesCallback) async {
    throw UnimplementedError();
  }
}
