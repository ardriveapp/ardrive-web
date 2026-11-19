import 'package:ardrive/gallery/data/arweave_gallery_image_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rateLimitFromError', () {
    test('429 and 503 from the gateway are rate limits', () {
      expect(rateLimitFromError(Exception('Gateway returned 429 for tx x')),
          isNotNull);
      expect(rateLimitFromError(Exception('Gateway returned 503 for tx x')),
          isNotNull);
    });

    test('other statuses and a 429 inside a tx id are not', () {
      expect(
          rateLimitFromError(
              Exception('Gateway returned 404 for tx ab-429-cd')),
          isNull);
      expect(
          rateLimitFromError(Exception('FetchCancelled: ab-429-cd')), isNull);
    });
  });
}
