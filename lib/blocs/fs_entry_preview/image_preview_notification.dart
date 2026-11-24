import 'dart:typed_data';

class ImagePreviewNotification {
  bool isLoading;
  Uint8List? dataBytes;
  String filename;
  String contentType;

  /// A photo too large to load without asking: its size, and what loads it.
  /// Full screen shows the same Preview prompt as the panel, since the panel
  /// is out of reach under it.
  int? onRequestSize;
  void Function()? loadOnRequest;

  /// The photo's thumbnail, shown while the original is on its way (or
  /// waits for Preview): soft for a moment rather than a spinner.
  Uint8List? placeholderBytes;

  bool get isPreviewable => dataBytes != null;

  ImagePreviewNotification({
    this.dataBytes,
    required this.filename,
    required this.contentType,
    this.isLoading = false,
    this.onRequestSize,
    this.loadOnRequest,
    this.placeholderBytes,
  });
}
