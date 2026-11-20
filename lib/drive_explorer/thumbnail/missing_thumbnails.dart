import 'dart:math' as math;

import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/utils/constants.dart';

/// What a file lacks of the thumbnails the app makes.
enum MissingThumbnails {
  /// It has what the gallery needs.
  none,

  /// It has none at all.
  all,

  /// It has only the small one, too small for a gallery tile.
  large,
}

/// A thumbnail at least this big on its longest side serves a gallery tile.
/// Lower than the 512 made today, so one made by another client at a nearby
/// size counts.
const int galleryReadyThumbnailSide = 400;

/// Below this an image gets no large thumbnail: an icon or a small graphic
/// has no 512 px to give, and would otherwise be offered one for ever.
const int largeThumbnailMinFileBytes = 256 * 1024;

/// What [variants] lack, for an image whose content type is [contentType]
/// and whose data is [size] bytes. [MissingThumbnails.none] for anything
/// thumbnails are not made for.
MissingThumbnails missingThumbnailsOf({
  required String? contentType,
  required int size,
  required List<Variant>? variants,
}) {
  if (!supportedImageTypesInFilePreview.contains(contentType)) {
    return MissingThumbnails.none;
  }
  if (variants == null || variants.isEmpty) return MissingThumbnails.all;
  if (size < largeThumbnailMinFileBytes) return MissingThumbnails.none;
  final hasLarge = variants.any(
    (v) => math.max(v.width, v.height) >= galleryReadyThumbnailSide,
  );
  return hasLarge ? MissingThumbnails.none : MissingThumbnails.large;
}
