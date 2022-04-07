import 'dart:html';
import 'dart:typed_data';

import 'package:ardrive/blocs/upload/upload_file.dart';
import 'package:file_selector/file_selector.dart';

class WebFile extends UploadFile {
  final File file;

  WebFile(this.file)
      : super(
          name: file.name,
          path: file.relativePath!,
          lastModifiedDate: file.lastModifiedDate,
          size: file.size,
        );

  @override
  Future<Uint8List> readAsBytes() async {
    final reader = FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;
    return reader.result as Uint8List;
  }
}

class DragAndDropFile extends UploadFile {
  final XFile file;
  @override
  final DateTime lastModifiedDate;
  @override
  final int size;
  DragAndDropFile._create(
    this.file,
    this.lastModifiedDate,
    this.size,
  ) : super(
          name: file.name,
          path: file.path,
          lastModifiedDate: lastModifiedDate,
          size: size,
        );

  static Future<DragAndDropFile> fromXFile(XFile file) async {
    final fileLastModified = await file.lastModified();
    final fileSize = await file.length();

    return DragAndDropFile._create(file, fileLastModified, fileSize);
  }

  @override
  Future<Uint8List> readAsBytes() => file.readAsBytes();
}
