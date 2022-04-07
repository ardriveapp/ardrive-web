import 'dart:html';
import 'dart:typed_data';

import 'package:ardrive/blocs/upload/upload_file.dart';

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
