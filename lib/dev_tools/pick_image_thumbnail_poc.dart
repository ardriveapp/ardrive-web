import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:universal_html/html.dart' as html;

Future<void> pickImageAndGenerateThumbnail({
  Function(Uint8List thumbnail)? onThumbnailGenerated,
}) async {
  html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
  uploadInput.accept = 'image/*';
  uploadInput.click();

  uploadInput.onChange.listen((e) async {
    final files = uploadInput.files;
    if (files?.length == 1) {
      final reader = html.FileReader();
      reader.readAsArrayBuffer(files![0]);
      reader.onLoadEnd.listen((e) async {
        final bytes = reader.result as Uint8List;
        final thumbnail = generateThumbnail(bytes);
        onThumbnailGenerated?.call(thumbnail);
        // Use the thumbnail as needed
      });
    }
  });
}

Uint8List generateThumbnail(Uint8List data) {
  final image = img.decodeImage(data);
  final thumbnail = img.copyResize(image!,
      width:
          100); // Resize the image to a width of 100 pixels, maintaining aspect ratio
  return Uint8List.fromList(img.encodePng(thumbnail));
}
