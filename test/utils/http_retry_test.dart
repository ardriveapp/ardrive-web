import 'package:ardrive/services/arweave/error/gateway_error.dart';
import 'package:ardrive/services/arweave/error/gateway_response_handler.dart';
import 'package:ardrive/utils/http_retry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';

void main() {
  HttpRetry sut = HttpRetry(GatewayResponseHandler());

  group('Testing HttpRetry class', () {
    const timeoutForWaitRetries = Timeout(Duration(minutes: 1));

    final success = Response('body', 200);
    final success250 = Response('body', 250);
    final success201 = Response('body', 201);

    final rateLimit = Response('body', 429);
    final unknownError = Response('body', 400);
    final unknownError300 = Response('body', 300);
    final serverError502 = Response('body', 502);
    final serverError500 = Response('body', 500);
    final serverError504 = Response('body', 504);

    test('processRequest method should return the response for success request',
        () async {
      final response = await sut.processRequest(() async => success);
      expect(response, success);
    }, timeout: timeoutForWaitRetries);

    test('processRequest method should return the response for success request',
        () async {
      final response = await sut.processRequest(() async => success201);
      expect(response, success201);
    }, timeout: timeoutForWaitRetries);
    test('processRequest method should return the response for success request',
        () async {
      final response = await sut.processRequest(() async => success250);
      expect(response, success250);
    }, timeout: timeoutForWaitRetries);
    test('processRequest method should return the response for success request',
        () async {
      final response = await sut.processRequest(() async => success201);
      expect(response, success201);
    }, timeout: timeoutForWaitRetries);
    test(
        'processRequest method should throw RateLimitError when response has status code 429',
        () async {
      expect(() async => await sut.processRequest(() async => rateLimit),
          throwsA(const TypeMatcher<RateLimitError>()));
    }, timeout: timeoutForWaitRetries);

    test(
        'processRequest method should throw UnknownNetworkError when response has status different from 2xx, 5xx or 429',
        () async {
      expect(() async => await sut.processRequest(() async => unknownError),
          throwsA(const TypeMatcher<UnknownNetworkError>()));
    }, timeout: timeoutForWaitRetries);

    test(
        'processRequest method should throw UnknownNetworkError when response has status different from 2xx, 5xx or 429',
        () async {
      expect(() async => await sut.processRequest(() async => unknownError300),
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
