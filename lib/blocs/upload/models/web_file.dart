// import 'dart:html';
import 'dart:typed_data';

import 'package:ardrive/blocs/upload/models/upload_file.dart';

class WebFile extends UploadFile {
  // final File file;
  @override
  final String parentFolderId;
  WebFile(
      // this.file,
      this.parentFolderId)
      : super(
          name: 'file.name',
          path: 'file.relativePath!',
          lastModifiedDate: DateTime.fromMillisecondsSinceEpoch(1),
          size: 1,
          parentFolderId: parentFolderId,
        );

  @override
  Future<Uint8List> readAsBytes() async {
    // final reader = FileReader();
    // reader.readAsArrayBuffer(file);
    // await reader.onLoad.first;
    // return reader.result as Uint8List;
    throw UnimplementedError();
  }

  @override
  String getIdentifier() {
    return path.isEmpty || _isPathBlobFromDragAndDrop(path) ? name : path;
  }

  bool _isPathBlobFromDragAndDrop(String path) {
    return path.split(':')[0] == 'blob';
  }
}
