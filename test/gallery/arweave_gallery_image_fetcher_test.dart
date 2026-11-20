import 'package:ardrive/download/download_exceptions.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/gallery/data/arweave_gallery_image_fetcher.dart';
import 'package:ardrive/gallery/image_loader/gallery_image_loader.dart';
import 'package:ardrive/gallery/image_loader/gallery_variant_picker.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockArweaveService extends Mock implements ArweaveService {}

class _MockFallback extends Mock implements DataGatewayFallback {}

class _MockClient extends Mock implements Arweave {}

class _MockDriveDao extends Mock implements DriveDao {}

class _MockThumbnails extends Mock implements ThumbnailRepository {}

void main() {
  group('fetch', () {
    test('a public file no gateway has fails as not found, not as a retry',
        () async {
      final arweave = _MockArweaveService();
      final fallback = _MockFallback();
      final client = _MockClient();
      when(() => arweave.gatewayFallback).thenReturn(fallback);
      when(() => arweave.client).thenReturn(client);
      when(() => fallback.fetchData('tx', client,
              cancelWhen: any(named: 'cancelWhen')))
          .thenThrow(TransactionNotFound('tx'));
      final fetcher = ArweaveGalleryImageFetcher(
        arweave: arweave,
        driveDao: _MockDriveDao(),
        thumbnailRepository: _MockThumbnails(),
      );
      await expectLater(
        fetcher.fetch(
          const GalleryFetchTarget(
            fileId: 'f',
            variant: GalleryVariant(txId: 'tx', size: 10, width: 1, height: 1),
            isPrivate: false,
            isOriginal: false,
          ),
          cancelWhen: Future<void>.delayed(const Duration(days: 1)),
        ),
        throwsA(isA<GalleryNotFound>()),
      );
    });
  });

  group('rateLimitFromError', () {
    test('GatewayRateLimited maps with its Retry-After', () {
      final e = rateLimitFromError(
        const GatewayRateLimited('x', retryAfter: Duration(seconds: 9)),
      );
      expect(e, isNotNull);
      expect(e!.retryAfter, const Duration(seconds: 9));
    });

    test('the downloader rate limit maps', () {
      expect(
          rateLimitFromError(const DownloadRateLimitException('x')), isNotNull);
    });

    test('a private download that ended on HTTP 429/503 maps', () {
      expect(
          rateLimitFromError(const DownloadNetworkException(
              'tx', 'HTTP 429 from https://g.example')),
          isNotNull);
      expect(
          rateLimitFromError(const DownloadNetworkException(
              'tx', 'HTTP 503 from https://g.example')),
          isNotNull);
    });

    test('other download network failures do not', () {
      expect(
          rateLimitFromError(const DownloadNetworkException(
              'tx', 'HTTP 500 from https://g.example')),
          isNull);
      expect(
          rateLimitFromError(
              const DownloadNetworkException('tx', 'timeout, tx ab-429-cd')),
          isNull);
      expect(rateLimitFromError(const DownloadNetworkException('tx')), isNull);
    });

    test('text that merely mentions 429 is not a rate limit', () {
      expect(
          rateLimitFromError(
              Exception('Gateway returned 404 for tx ab-429-cd')),
          isNull);
      expect(rateLimitFromError(Exception('Gateway returned 429 for tx x')),
          isNull);
      expect(rateLimitFromError(const FetchCancelled('ab-429-cd')), isNull);
    });
  });
}
