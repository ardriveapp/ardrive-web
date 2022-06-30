import 'package:ardrive/services/arweave/error/error.dart';
import 'package:ardrive/services/arweave/error/response_handler.dart';
import 'package:ardrive/services/arweave/http_retry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';

void main() {
  HttpRetry sut = HttpRetry(GatewayResponseHandler());

  group('Testing HttpRetry class', () {
    const timeoutForWaitRetries = Timeout(Duration(minutes: 1));

    final success = Response('body', 200);
    final rateLimit = Response('body', 429);
    final unknownError = Response('body', 400);
    final serverError502 = Response('body', 502);
    final serverError500 = Response('body', 500);
    final serverError504 = Response('body', 504);

    test(
        'processRequest method should return the response when dont have any error',
        () async {
      final response = await sut.processRequest(() async => success);
      expect(response, success);
    }, timeout: timeoutForWaitRetries);

    test(
        'processRequest method should throw RateLimitError when response has status code 429',
        () async {
      expect(() async => await sut.processRequest(() async => rateLimit),
          throwsA(const TypeMatcher<RateLimitError>()));
    }, timeout: timeoutForWaitRetries);

    test(
        'processRequest method should throw UnknownNetworkError when response has status different from 5xx or 429',
        () async {
      expect(() async => await sut.processRequest(() async => unknownError),
          throwsA(const TypeMatcher<UnknownNetworkError>()));
    }, timeout: timeoutForWaitRetries);

    test(
        'processRequest method should throw ServerError for response with status code 502',
        () async {
      expect(() async => await sut.processRequest(() async => serverError502),
          throwsA(const TypeMatcher<ServerError>()));
    }, timeout: timeoutForWaitRetries);

    test(
        'processRequest method should throw ServerError for response with status code 504',
        () async {
      expect(() async => await sut.processRequest(() async => serverError504),
          throwsA(const TypeMatcher<ServerError>()));
    }, timeout: timeoutForWaitRetries);

    test(
        'processRequest method should throw ServerError for response with status code 500',
        () async {
      expect(() async => await sut.processRequest(() async => serverError500),
          throwsA(const TypeMatcher<ServerError>()));
    }, timeout: timeoutForWaitRetries);
  });
}
