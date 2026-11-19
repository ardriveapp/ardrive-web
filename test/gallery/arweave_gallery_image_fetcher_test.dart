import 'package:ardrive/download/download_exceptions.dart';
import 'package:ardrive/gallery/data/arweave_gallery_image_fetcher.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
