import 'package:ardrive/utils/error.dart';
import 'package:ardrive/utils/network_error_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';

void main() {
  final sut = NetworkErrorHandler();

  final rateLimit = Response('body', 429);
  final unknownError = Response('body', 400);
  final serverError502 = Response('body', 502);
  group('description', () {
    test('should return ServerError', () {
      expect(ServerError(statusCode: 502, reasonPhrase: ''),
          sut.handle(serverError502));
    });
    test('should return RateLimitError', () {
      expect(RateLimitError(reasonPhrase: ''), sut.handle(rateLimit));
    });
    test('should return UnknowNetworkError', () {
      expect(UnknownNetworkError(statusCode: 400, reasonPhrase: ''),
          sut.handle(unknownError));
    });
  });
}
