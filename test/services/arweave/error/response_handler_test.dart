import 'package:ardrive/services/arweave/error/error.dart';
import 'package:ardrive/services/arweave/error/response_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';

void main() {
  final sut = GatewayResponseHandler();
  final success = Response('body', 200);
  final rateLimit = Response('body', 429);
  final unknownError = Response('body', 400);
  final serverError502 = Response('body', 502);
  group('Testing GatewayResponseHandler class', () {
    test('should return the response for success', () {
      /// Should not throw exception. We can do `expect(null, null);` safely here as this function
      /// doesnt return nothing in case of success.
      sut.handle(success);
      expect(null, null);
    });
    test('should throws a ServerError', () {
      expect(() => sut.handle(serverError502),
          throwsA(const TypeMatcher<ServerError>()));
    });
    test('should return RateLimitError', () {
      expect(() => sut.handle(rateLimit),
          throwsA(const TypeMatcher<RateLimitError>()));
    });
    test('should return UnknowNetworkError', () {
      expect(() => sut.handle(unknownError),
          throwsA(const TypeMatcher<UnknownNetworkError>()));
    });
  });
}
