import 'dart:typed_data';

class ImagePreviewNotification {
  bool isLoading;
  Uint8List? dataBytes;
  String? filename;
  String? contentType;

  bool get isPreviewable =>
      dataBytes != null && filename != null && contentType != null;

  ImagePreviewNotification({
    this.dataBytes,
    this.filename,
    this.contentType,
    this.isLoading = false,
  });

  @override
  String toString() {
    return 'ImagePreviewNotification{isLoading: $isLoading, dataBytes: $dataBytes, filename: $filename, contentType: $contentType}';
  }
}
