import 'dart:typed_data';

import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/gallery/image_loader/gallery_image_loader.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave.dart';

/// The production [GalleryImageFetcher].
///
/// Private files go through [ThumbnailRepository.fetchPrivateVariantBytes],
/// the same download-and-decrypt path the list view's thumbnails use. Public
/// files are read through the data gateway waterfall, which supports aborting
/// via `cancelWhen`.
class ArweaveGalleryImageFetcher implements GalleryImageFetcher {
  ArweaveGalleryImageFetcher({
    required ArweaveService arweave,
    required DriveDao driveDao,
    required ThumbnailRepository thumbnailRepository,
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _thumbnails = thumbnailRepository;

  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ThumbnailRepository _thumbnails;

  @override
  Future<Uint8List> fetch(
    GalleryFetchTarget target, {
    required Future<void> cancelWhen,
  }) async {
    try {
      if (target.isPrivate) {
        // Private originals are never loaded in the grid, so this is always a
        // thumbnail variant.
        final file = await (_driveDao.select(_driveDao.fileEntries)
              ..where((t) => t.id.equals(target.fileId)))
            .getSingle();
        return await _thumbnails.fetchPrivateVariantBytes(
          fileId: file.id,
          driveId: file.driveId,
          txId: target.variant.txId,
          size: target.variant.size,
          fileName: file.name,
          lastModifiedDate: file.lastModifiedDate,
        );
      }

      final response = await _arweave.gatewayFallback.fetchData(
        target.variant.txId,
        _arweave.client,
        cancelWhen: cancelWhen,
      );
      return response.bodyBytes;
    } catch (e) {
      final limited = rateLimitFromError(e);
      if (limited != null) throw limited;
      rethrow;
    }
  }
}

/// The gateway layers surface HTTP failures as exceptions whose text carries
/// the status ("Gateway returned 429 for tx ..."), without the headers, so
/// Retry-After is not available here and the loader falls back to its own
/// backoff.
GalleryRateLimited? rateLimitFromError(Object error) {
  final text = error.toString();
  // Anchored to the gateway's wording: a bare 429 could be part of a tx ID.
  if (RegExp(r'\breturned (429|503)\b').hasMatch(text) &&
      !text.contains('FetchCancelled')) {
    return const GalleryRateLimited();
  }
  return null;
}
