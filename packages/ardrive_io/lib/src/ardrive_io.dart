import 'dart:async';

import 'package:flutter/foundation.dart';

import 'file_provider.dart';
import 'io_file.dart';
import 'io_folder.dart';
import 'mobile/mobile_io.dart';
import 'web/stub_web_io.dart' // Stub implementation
    if (dart.library.html) 'web/web_io.dart';

class SaveStatus {
  final int bytesSaved;
  final int totalBytes;
  final bool? saveResult;

  SaveStatus({
    required this.bytesSaved,
    required this.totalBytes,
    this.saveResult,
  });
}

/// API for I/O operations
///
/// Opens the platform specific file picker to pick files and folders, and save files using
/// the `IOFile` and `IOFolder` APIs.
abstract class ArDriveIO {
  factory ArDriveIO() {
    if (kIsWeb) {
      return WebIO(fileProviderFactory: FileProviderFactory());
    }

    return MobileIO(
      fileSaver: FileSaver(),
      folderAdapter: IOFolderAdapter(),
      fileProviderFactory: FileProviderFactory(),
    );
  }
  Future<IOFile> pickFile({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  });
  Future<List<IOFile>> pickFiles({
    List<String>? allowedExtensions,
    required FileSource fileSource,
  });
  Future<IOFolder> pickFolder();

  Future<void> saveFile(IOFile file);

  Stream<SaveStatus> saveFileStream(IOFile file, Completer<bool> finalize);
}
