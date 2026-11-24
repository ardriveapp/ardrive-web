import 'dart:typed_data';

import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/gallery/image_loader/gallery_image_loader.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/logger.dart';

/// A thumbnail bigger than this is not fetched to stand in: the stand-in is
/// meant to be the cheap, quick part.
const int previewPlaceholderMaxBytes = 512 * 1024;

/// The photo's thumbnail, for the preview to show while the original loads:
/// the largest one the gallery already holds, which costs nothing, or, with
/// [allowFetch], one small fetch of the largest thumbnail the file has. Null
/// when there is none, or it could not be had.
Future<Uint8List?> previewPlaceholderFor(
  FileDataTableItem item, {
  bool allowFetch = true,
  required bool isPrivate,
  required GalleryImageLoader? loader,
  required ThumbnailRepository thumbnails,
  required ArweaveService arweave,
}) async {
  final variants = [...?item.thumbnail?.variants]
    ..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
  if (variants.isEmpty) return null;

  if (loader != null) {
    for (final variant in variants) {
      final held = loader.cachedBytes(item.id, variant.txId);
      if (held != null) return held;
    }
  }

  if (!allowFetch) return null;
  final best = variants.first;
  if (best.size > previewPlaceholderMaxBytes) return null;
  try {
    if (isPrivate) {
      return await thumbnails.fetchPrivateVariantBytes(
        fileId: item.id,
        driveId: item.driveId,
        txId: best.txId,
        size: best.size,
        fileName: item.name,
        lastModifiedDate: item.lastModifiedDate,
      );
    }
    return await arweave.gatewayFallback.fetchDataAtMost(
      best.txId,
      arweave.client,
      maxBytes: previewPlaceholderMaxBytes,
    );
  } catch (e) {
    logger.d('No thumbnail to show while the photo loads: $e');
    return null;
  }
}
