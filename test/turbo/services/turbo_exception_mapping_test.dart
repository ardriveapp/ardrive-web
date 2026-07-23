import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('turboExceptionForStatusCode', () {
    test('maps 408 to a timeout exception', () {
      expect(
        turboExceptionForStatusCode(408),
        isA<TurboUploadTimeoutException>(),
      );
    });

    test('maps 402 to a payment-required exception', () {
      expect(
        turboExceptionForStatusCode(402),
        isA<TurboPaymentRequiredException>(),
      );
    });

    test('maps 429 to a rate-limit exception', () {
      expect(
        turboExceptionForStatusCode(429),
        isA<TurboRateLimitException>(),
      );
    });

    test('returns null for codes without special semantics', () {
      expect(turboExceptionForStatusCode(500), isNull);
      expect(turboExceptionForStatusCode(400), isNull);
      expect(turboExceptionForStatusCode(null), isNull);
    });

    test('payment and rate-limit exceptions are TurboUploadExceptions', () {
      // The metadata-op blocs distinguish payment failures by type; the
      // hierarchy must hold or their dialogs regress to generic errors.
      expect(
        turboExceptionForStatusCode(402),
        isA<TurboUploadExceptions>(),
      );
      expect(
        turboExceptionForStatusCode(429),
        isA<TurboUploadExceptions>(),
      );
    });
  });
}
