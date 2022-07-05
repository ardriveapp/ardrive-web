import 'package:ardrive/utils/http_retry.dart';
import 'package:ardrive/utils/response_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:mocktail/mocktail.dart';

class MockResponseHandler extends Mock implements ResponseHandler {}

class MockHttpRetryOptions extends Mock implements HttpRetryOptions {}

void main() {
  const timeoutForWaitRetries = Timeout(Duration(minutes: 1));
  const retryMaxAttempts = 8;

  final mockResponseHandler = MockResponseHandler();
  final mockRetryHttpOptions = MockHttpRetryOptions();

  HttpRetry sut = HttpRetry(mockResponseHandler, mockRetryHttpOptions);

  group('testing HttpRetry class', () {
    final tResponse = Response('body', 200);

    setUp(() {
      registerFallbackValue(tResponse);
    });

    test('should return the response when dont have any errors', () async {
      when(() => mockResponseHandler.handle(any())).thenAnswer((i) => Null);

      final response = await sut.processRequest(() async => tResponse);
      expect(response, tResponse);
    });

    test('should retry $retryMaxAttempts times and then throw when ResponseHandler throws', () async {
      when(() => mockResponseHandler.handle(any())).thenThrow(Exception());
      when(() => mockRetryHttpOptions.onRetry!(any()))
          .thenAnswer((i) => print('calling the callback...'));
      await expectLater(() => sut.processRequest(() async => tResponse),
          throwsA(const TypeMatcher<Exception>()));

      /// Verifies if has retried the expected times
      /// 
      /// On the last attempt, it will return the response in case of success
      /// or throw the exception in case of failure, so the `onRetry` function
      /// won't be called in the last time.
      verify(
        () => mockRetryHttpOptions.onRetry?.call(any()),
      ).called(retryMaxAttempts - 1);
    }, timeout: timeoutForWaitRetries);
  });
}
