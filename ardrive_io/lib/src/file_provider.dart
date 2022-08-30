import 'package:ardrive_io/ardrive_io.dart';

abstract class FileProvider {
  Future<IOFile> pickFile(List<String>? allowedExtensions);
  Future<List<IOFile>> pickMultipleFiles(List<String>? allowedExtensions);
}

/// `gallery` device's gallery
/// `fileSystem` device's file system
///
/// on **Web** `gallery` is not supported.
enum FileSource { gallery, fileSystem }
