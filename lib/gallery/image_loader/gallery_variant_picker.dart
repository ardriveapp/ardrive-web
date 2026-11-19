/// One stored rendition of an image: a thumbnail variant, or the original.
class GalleryVariant {
  const GalleryVariant({
    required this.txId,
    required this.size,
    required this.width,
    required this.height,
  });

  final String txId;

  /// Bytes on the gateway (ciphertext size for a private file).
  final int size;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is GalleryVariant &&
      other.txId == txId &&
      other.size == size &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(txId, size, width, height);

  @override
  String toString() => 'GalleryVariant($txId, $size B, ${width}x$height)';
}

/// What the loader will fetch for a tile.
class GalleryVariantChoice {
  const GalleryVariantChoice(this.variant, {required this.isOriginal});

  final GalleryVariant variant;
  final bool isOriginal;

  @override
  String toString() => 'GalleryVariantChoice($variant, original: $isOriginal)';
}

/// Largest public original the grid will load in place of a missing or too
/// small thumbnail.
const int galleryMaxOriginalBytes = 2 * 1024 * 1024;

/// Chooses the rendition for a tile of [tileWidthPx] x [tileHeightPx] device
/// pixels. Pure, so the whole policy is a table in the tests.
///
/// - The smallest variant (by pixel area) that covers the tile in both
///   dimensions; if none does, the largest variant.
/// - The original only when [isPrivate] is false, it is at most
///   [maxOriginalBytes], the tile is [onScreen] and the loader is [idle], and
///   no variant covers the tile (no thumbnails at all, or only small ones).
///   Private drives never load originals in the grid.
/// - An original with a size of 0 or less (unknown) is never eligible, and
///   variants with unknown (0) dimensions never cover and rank last.
/// - null when there is nothing eligible to load.
GalleryVariantChoice? chooseGalleryVariant({
  required List<GalleryVariant> variants,
  required double tileWidthPx,
  required double tileHeightPx,
  required bool isPrivate,
  GalleryVariant? original,
  bool onScreen = true,
  bool idle = true,
  int maxOriginalBytes = galleryMaxOriginalBytes,
}) {
  GalleryVariant? covering;
  GalleryVariant? largest;
  for (final v in variants) {
    if (largest == null || _outranks(v, largest)) largest = v;
    if (v.width >= tileWidthPx && v.height >= tileHeightPx) {
      if (covering == null || _area(v) < _area(covering)) covering = v;
    }
  }

  if (covering != null) {
    return GalleryVariantChoice(covering, isOriginal: false);
  }

  final originalAllowed = !isPrivate &&
      original != null &&
      original.size > 0 &&
      original.size <= maxOriginalBytes &&
      onScreen &&
      idle;
  if (originalAllowed) {
    return GalleryVariantChoice(original, isOriginal: true);
  }

  if (largest != null) {
    return GalleryVariantChoice(largest, isOriginal: false);
  }
  return null;
}

int _area(GalleryVariant v) =>
    v.width > 0 && v.height > 0 ? v.width * v.height : 0;

/// Bigger by pixels; variants with unknown dimensions rank last, by size.
bool _outranks(GalleryVariant a, GalleryVariant b) {
  final aa = _area(a), ab = _area(b);
  if (aa != ab) return aa > ab;
  return a.size > b.size;
}
