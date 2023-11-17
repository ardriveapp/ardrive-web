import 'dart:typed_data';

class ImagePreviewNotification {
  bool isLoading;
  Uint8List? dataBytes;
  String? filename;
  String? contentType;

  bool get isPreviewable => dataBytes != null;

  ImagePreviewNotification({
    this.dataBytes,
    this.filename,
    this.contentType,
    this.isLoading = false,
  });
}
