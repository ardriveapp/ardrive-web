import 'package:ardrive/services/arweave/error/gateway_error.dart';
import 'package:ardrive/services/arweave/error/gateway_response_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';

void main() {
  final sut = GatewayResponseHandler();
  final success = Response('body', 200);
  final success208 = Response('body', 208);
  final success201 = Response('body', 201);

  final rateLimit = Response('body', 429);
  final unknownError = Response('body', 400);
  final unknownError300 = Response('body', 300);
  final serverError502 = Response('body', 502);
  final unExpectedRedirection = Response('body', 302);

  group('Testing GatewayResponseHandler class', () {
    test('should return null for success', () {
      /// Should not throw exception. We can do `expect(null, null);` safely here as this function
      /// doesnt return nothing in case of success.
      sut.handle(success);
      expect(null, null);
    });
    test('should return null for success', () {
      /// Should not throw exception. We can do `expect(null, null);` safely here as this function
      /// doesnt return nothing in case of success.
      sut.handle(success208);
      expect(null, null);
    });
    test('should return null for success', () {
      /// Should not throw exception. We can do `expect(null, null);` safely here as this function
      /// doesnt return nothing in case of success.
      sut.handle(success201);
      expect(null, null);
    });
    test('should throws a ServerError', () {
      expect(() => sut.handle(serverError502),
          throwsA(const TypeMatcher<ServerError>()));
    });
    test('should throws a UnexpectedRedirection', () {
      expect(() => sut.handle(unExpectedRedirection),
          throwsA(const TypeMatcher<UnexpectedRedirection>()));
    });
    test('should return RateLimitError', () {
      expect(() => sut.handle(rateLimit),
          throwsA(const TypeMatcher<RateLimitError>()));
    });
    test('should return UnknowNetworkError', () {
      expect(() => sut.handle(unknownError),
          throwsA(const TypeMatcher<UnknownNetworkError>()));
    });
    test('should return UnknowNetworkError', () {
      expect(() => sut.handle(unknownError300),
          throwsA(const TypeMatcher<UnknownNetworkError>()));
    });
  });
}
