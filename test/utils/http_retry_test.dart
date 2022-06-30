import 'package:ardrive/utils/http_retry.dart';
import 'package:ardrive/utils/response_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:mocktail/mocktail.dart';

class MockResponseHandler extends Mock implements ResponseHandler {}

void main() {
  const timeoutForWaitRetries = Timeout(Duration(minutes: 1));

  final mockResponseHandler = MockResponseHandler();
  HttpRetry sut = HttpRetry(mockResponseHandler);

  group('Testing HttpRetry class', () {
    final tResponse = Response('body', 200);

    setUp(() {
      registerFallbackValue(tResponse);
    });

    test('Should return the response when dont have any errors', () async {
      when(() => mockResponseHandler.handle(any())).thenAnswer((i) => null);
      final response = await sut.processRequest(() async => tResponse);
      expect(response, tResponse);
    });

    test('Should retry and throw when ResponseHandler throws', () async {
      when(() => mockResponseHandler.handle(any())).thenThrow(Exception());

      expect(await sut.processRequest(() async => tResponse),
          throwsA(const TypeMatcher<Exception>()));
    }, timeout: timeoutForWaitRetries);
  });
}
