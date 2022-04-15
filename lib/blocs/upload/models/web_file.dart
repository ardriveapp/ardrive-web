import 'dart:html';
import 'dart:typed_data';

import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:file_selector/file_selector.dart';

class WebFile extends UploadFile {
  final File file;
  @override
  final String parentFolderId;
  WebFile(this.file, this.parentFolderId)
      : super(
          name: file.name,
          path: file.relativePath!,
          lastModifiedDate:
              DateTime.fromMillisecondsSinceEpoch(file.lastModified!),
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

