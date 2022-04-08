import 'dart:html';
import 'dart:typed_data';

import 'package:ardrive/blocs/upload/upload_file.dart';
import 'package:file_selector/file_selector.dart';

class WebFile extends UploadFile {
  final File file;
  @override
  final String parentFolderId;
  WebFile(this.file, this.parentFolderId)
      : super(
          name: file.name,
          path: file.relativePath!,
          lastModifiedDate: file.lastModifiedDate,
          size: file.size,
          parentFolderId: parentFolderId,
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

  @override
  final String parentFolderId;

  DragAndDropFile._create(
    this.file,
    this.lastModifiedDate,
    this.size,
    this.parentFolderId,
  ) : super(
          name: file.name,
          path: file.path,
          lastModifiedDate: lastModifiedDate,
          size: size,
          parentFolderId: parentFolderId,
        );

  static Future<DragAndDropFile> fromXFile(
      XFile file, String parentFolderId) async {
    final fileLastModified = await file.lastModified();
    final fileSize = await file.length();

    return DragAndDropFile._create(
      file,
      fileLastModified,
      fileSize,
      parentFolderId,
    );
  }

  @override
  Future<Uint8List> readAsBytes() => file.readAsBytes();
}
