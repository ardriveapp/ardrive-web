import 'dart:typed_data';

abstract class UploadFile {
  String name;
  String path;
  DateTime lastModifiedDate;
  int size;
  Future<Uint8List> readAsBytes();

  UploadFile({
    required this.name,
    required this.path,
    required this.lastModifiedDate,
    required this.size,
  });
}
