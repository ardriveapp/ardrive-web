import 'dart:typed_data';

import 'package:ardrive/download/download_exceptions.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/gallery/image_loader/gallery_image_loader.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';

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

/// Maps the rate-limit failures of the two fetch paths to the loader's.
///
/// - [GatewayRateLimited] from the data gateway waterfall (public files), with
///   its Retry-After.
/// - [DownloadNetworkException] from the downloader (private files). The
///   downloader never throws [DownloadRateLimitException]; when every gateway
///   answers 429 its `_openRange` ends in
///   `DownloadNetworkException(txId, lastError)` with `lastError` of the form
///   'HTTP 429 from <origin>' (ardrive_downloader.dart, `lastError = 'HTTP
///   ${response.statusCode} from $origin'`). The downloader is left alone as
///   its exception types feed preview and download retry logic.
///   [DownloadRateLimitException] is still mapped in case it is ever thrown.
///
/// Null for anything else.
GalleryRateLimited? rateLimitFromError(Object error) {
  if (error is GatewayRateLimited) {
    return GalleryRateLimited(retryAfter: error.retryAfter);
  }
  if (error is DownloadRateLimitException) {
    return const GalleryRateLimited();
  }
  if (error is DownloadNetworkException) {
    final last = error.lastError;
    if (last != null && RegExp(r'^HTTP (429|503)\b').hasMatch(last)) {
      return const GalleryRateLimited();
    }
  }
  return null;
}
