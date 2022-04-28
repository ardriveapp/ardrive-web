import 'dart:typed_data';

abstract class UploadFile {
  String name;
  String path;
  DateTime lastModifiedDate;
  int size;
  String parentFolderId;
  Future<Uint8List> readAsBytes();

  String getIdentifier();

  UploadFile({
    required this.name,
    required this.path,
    required this.lastModifiedDate,
    required this.parentFolderId,
    required this.size,
  });
}
