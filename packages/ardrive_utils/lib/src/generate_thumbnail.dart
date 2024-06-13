import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

enum ThumbnailSize {
  small,
  medium,
  large,
}

Future<ThumbnailGenerationResult> generateThumbnail(
  Uint8List data,
  ThumbnailSize size,
) async {
  var result = await FlutterImageCompress.compressWithList(
    data,
    minHeight: 100,
    minWidth: 100,
    quality: 95,
  );

  final thumbnail = img.decodeImage(result)!;

  debugPrint('Thumbnail size: ${thumbnail.length}');

  return ThumbnailGenerationResult(
    thumbnail: img.encodeJpg(thumbnail),
    size: thumbnail.length,
    height: thumbnail.height,
    width: thumbnail.width,
    aspectRatio: thumbnail.width ~/ thumbnail.height,
    name: size.name,
  );
}

class ThumbnailGenerationResult {
  final Uint8List thumbnail;
  final int size;
  final int height;
  final int width;
  final int aspectRatio;
  final String name;

  ThumbnailGenerationResult({
    required this.thumbnail,
    required this.size,
    required this.height,
    required this.width,
    required this.aspectRatio,
    required this.name,
  });
}
