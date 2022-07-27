import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_io/src/io_exception.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:file_selector/file_selector.dart';

/// Web implementation to use `ArDriveIO` API
///
class WebIO implements ArDriveIO {
  WebIO({required IOFileAdapter fileAdapter}) : _fileAdapter = fileAdapter;

  final IOFileAdapter _fileAdapter;

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
    throw UnimplementedError();
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
