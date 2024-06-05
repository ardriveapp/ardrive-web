import 'dart:typed_data';

import 'package:image/image.dart' as img;

Uint8List generateThumbnail(Uint8List data) {
  final image = img.decodeImage(data);
  final thumbnail = img.copyResize(image!,
      width:
          100); // Resize the image to a width of 100 pixels, maintaining aspect ratio
  return Uint8List.fromList(img.encodePng(thumbnail));
}
