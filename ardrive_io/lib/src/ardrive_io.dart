import 'dart:async';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter/foundation.dart';

import 'mobile/mobile_io.dart';
import 'web/stub_web_io.dart' // Stub implementation
    if (dart.library.html) 'web/web_io.dart';

abstract class ArDriveIO {
  Future<IOFile> pickFile({List<String>? allowedExtensions});
  Future<List<IOFile>> pickFiles({List<String>? allowedExtensions});
  Future<IOFolder> pickFolder();
  Future<void> saveFile(IOFile file);

  factory ArDriveIO() {
    if (kIsWeb) {
      return WebIO(
          fileAdapter: IOFileAdapter(),
          folderAdapter: IOFolderAdapter(),
          folderPicker: FolderPicker());
    }

    return MobileIO(
        fileSaver: FileSaver(),
        fileAdapter: IOFileAdapter(),
        folderAdapter: IOFolderAdapter());
  }
}
