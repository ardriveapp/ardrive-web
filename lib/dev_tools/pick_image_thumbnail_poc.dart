import 'dart:typed_data';

import 'package:ardrive_utils/ardrive_utils.dart';
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
