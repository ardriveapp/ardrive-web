import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// The images a publication can have (docs/PUBLICATIONS.md, "Step 3 ·
/// Look"), their sizes, and how an owner's picture becomes one.
///
/// The browser decodes the picture, so anything it can show works (PNG,
/// JPEG, WebP, GIF), and a canvas crops and scales it. Icons are written as
/// PNG; the cover and social card as JPEG, as small as their byte budget
/// allows without going below a quality floor.
enum PublicationImageKind {
  icon(width: 512, height: 512),
  cover(width: 1600, height: 400),
  social(width: 1200, height: 630);

  const PublicationImageKind({required this.width, required this.height});

  final int width;
  final int height;

  double get aspect => width / height;
}

/// The largest picture an owner can pick, before it is made smaller.
const publicationImageMaxBytes = 20 * 1024 * 1024;

/// What a JPEG aims to stay under.
const publicationJpegBudgetBytes = 100 * 1024;

/// A page's files for one picked image, by manifest path.
typedef PublicationImageFiles = Map<String, Uint8List>;

class PublicationImageException implements Exception {
  const PublicationImageException(this.reason);

  final PublicationImageProblem reason;

  @override
  String toString() => 'PublicationImageException($reason)';
}

enum PublicationImageProblem { tooLarge, notAnImage }

/// A picked picture, decoded.
class PublicationPicture {
  PublicationPicture._(this.image);

  final ui.Image image;

  int get width => image.width;
  int get height => image.height;

  /// Whether it is smaller than [kind] is shown at, so it will look soft.
  bool isSmallFor(PublicationImageKind kind) {
    final scale = math.max(kind.width / width, kind.height / height);
    return scale > 1;
  }

  /// Throws [PublicationImageException].
  static Future<PublicationPicture> decode(Uint8List bytes) async {
    if (bytes.length > publicationImageMaxBytes) {
      throw const PublicationImageException(PublicationImageProblem.tooLarge);
    }
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return PublicationPicture._(frame.image);
    } catch (_) {
      throw const PublicationImageException(PublicationImageProblem.notAnImage);
    }
  }

  void dispose() => image.dispose();
}

/// Draws [picture] into a [width] × [height] image, cropped to its middle to
/// fill it, the way a cover shows.
Future<ui.Image> publicationCrop(ui.Image picture, int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paintCovering(
      canvas, picture, Rect.fromLTWH(0, 0, width * 1.0, height * 1.0));
  return recorder.endRecording().toImage(width, height);
}

/// Paints [picture] over [area], cropped to its middle to fill it.
void paintCovering(Canvas canvas, ui.Image picture, Rect area) {
  final source = Size(picture.width * 1.0, picture.height * 1.0);
  final fitted = applyBoxFit(BoxFit.cover, source, area.size);
  final from = Alignment.center.inscribe(fitted.source, Offset.zero & source);
  canvas.drawImageRect(
    picture,
    from,
    area,
    Paint()..filterQuality = FilterQuality.high,
  );
}

Future<Uint8List> publicationPng(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// [image] as a JPEG under [budget] bytes if a quality of 60 or more gets
/// there, else at 60.
Future<Uint8List> publicationJpeg(
  ui.Image image, {
  int budget = publicationJpegBudgetBytes,
}) async {
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final pixels = img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: rgba!.buffer,
    numChannels: 4,
  );
  Uint8List jpeg = Uint8List(0);
  for (final quality in const [85, 78, 70, 60]) {
    jpeg = img.encodeJpg(pixels, quality: quality);
    if (jpeg.length < budget) break;
  }
  return jpeg;
}

/// The page files for an icon: 512, 180 and 32 pixel PNGs.
Future<PublicationImageFiles> publicationIconFiles(ui.Image picture) async {
  return {
    for (final size in const [32, 180, 512])
      'icon-$size.png':
          await publicationPng(await publicationCrop(picture, size, size)),
  };
}

/// The page file for a cover or an owner's own social card.
Future<Uint8List> publicationBannerFile(
  ui.Image picture,
  PublicationImageKind kind,
) async =>
    publicationJpeg(await publicationCrop(picture, kind.width, kind.height));
