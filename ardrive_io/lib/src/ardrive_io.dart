import 'dart:async';
import 'dart:io';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter/foundation.dart';

import 'io_exception.dart';
import 'mobile/mobile_io.dart';

abstract class ArDriveIO {
  Future<IOFile> pickFile({List<String>? allowedExtensions});
  Future<List<IOFile>> pickFiles({List<String>? allowedExtensions});
  Future<IOFolder> pickFolder();
  Future<void> saveFile(IOFile file);

  factory ArDriveIO() {
    if (kIsWeb) {
      throw UnsupportedPlatformException(
          'The ${Platform.operatingSystem} platform is not supported.');
    }

    return MobileIO(
        fileSaver: FileSaver(),
        fileAdapter: IOFileAdapter(),
        folderAdapter: IOFolderAdapter());
  }
}
