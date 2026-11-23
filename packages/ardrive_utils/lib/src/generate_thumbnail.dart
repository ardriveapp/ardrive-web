import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

enum ThumbnailSize {
  small,
  medium,
  large,
}

/// The longest side of the large thumbnail, the one the gallery shows.
const int largeThumbnailMaxSide = 512;

/// The thumbnails an image gets: the small one first, which older clients
/// read as `variants.first`, then a large one when the image is big enough
/// for it to add anything.
Future<List<ThumbnailGenerationResult>> generateThumbnails(
  Uint8List data,
) async {
  final small = await generateThumbnail(data, ThumbnailSize.small);
  try {
    final large = await _generateLarge(data, small);
    return [small, if (large != null) large];
  } catch (e) {
    // The small one is what every client needs; the large one is a bonus.
    debugPrint('Large thumbnail failed: $e');
    return [small];
  }
}

Future<ThumbnailGenerationResult?> _generateLarge(
  Uint8List data,
  ThumbnailGenerationResult small,
) async {
  final target = largeThumbnailSizeFor(
    width: small.width,
    height: small.height,
  );
  final result = await FlutterImageCompress.compressWithList(
    data,
    // The web reads only the width, and never scales up; elsewhere these
    // are minimums. Both are given in the image's own proportions.
    minWidth: target.width,
    minHeight: target.height,
    quality: 85,
  );
  // Decoded only for its size; the compressor's JPEG is used as it is.
  final large = img.decodeImage(result)!;
  if (!isWorthALargeThumbnail(
    largeWidth: large.width,
    largeHeight: large.height,
    smallWidth: small.width,
    smallHeight: small.height,
  )) {
    return null;
  }
  // Not worth storing a thumbnail as big as the image it stands for.
  if (result.length >= data.length) return null;
  return ThumbnailGenerationResult(
    thumbnail: result,
    size: result.length,
    height: large.height,
    width: large.width,
    name: ThumbnailSize.large.name,
  );
}

/// The large thumbnail's size for an image in the proportions of
/// [width] x [height]: its longest side is [largeThumbnailMaxSide].
({int width, int height}) largeThumbnailSizeFor({
  required int width,
  required int height,
}) {
  if (width <= 0 || height <= 0) {
    return (width: largeThumbnailMaxSide, height: largeThumbnailMaxSide);
  }
  if (width >= height) {
    return (
      width: largeThumbnailMaxSide,
      height: math.max(1, (largeThumbnailMaxSide * height / width).round()),
    );
  }
  return (
    width: math.max(1, (largeThumbnailMaxSide * width / height).round()),
    height: largeThumbnailMaxSide,
  );
}

/// Whether a large thumbnail adds to the small one: not when the image was
/// too small to make one much bigger. Measured on the longest side, as the
/// small one of a tall image is already tall.
bool isWorthALargeThumbnail({
  required int largeWidth,
  required int largeHeight,
  required int smallWidth,
  required int smallHeight,
}) =>
    math.max(largeWidth, largeHeight) > 1.5 * math.max(smallWidth, smallHeight);

/// The small thumbnail, about 100 px wide, that every client shows.
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

  // Quality 85: at 100 px the default of 100 made thumbnails of 20 to 60 KB
  // that look no better than ones of a few.
  return ThumbnailGenerationResult(
    thumbnail: img.encodeJpg(thumbnail, quality: 85),
    size: thumbnail.length,
    height: thumbnail.height,
    width: thumbnail.width,
    name: size.name,
  );
}

class ThumbnailGenerationResult {
  final Uint8List thumbnail;
  final int size;
  final int height;
  final int width;
  final String name;

  ThumbnailGenerationResult({
    required this.thumbnail,
    required this.size,
    required this.height,
    required this.width,
    required this.name,
  });
}
