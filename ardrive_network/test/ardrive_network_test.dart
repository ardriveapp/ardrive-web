import 'package:ardrive_network/ardrive_network.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import './webserver.dart';

const baseUrl = 'http://localhost:8080';

void main() {
  group('ArdriveNetwork', () {
    final ardriveNetwork = ArdriveNetwork(
      retryDelayMs: 0,
      noLogs: true,
    );

    test('can be instantiated', () {
      expect(ardriveNetwork, isNotNull);
    });

    group('get method', () {
      test('throws when isJson and asBytes are used together', () async {
        final response = ardriveNetwork.get(
          url: baseUrl,
          isJson: true,
          asBytes: true,
        );

        expect(() => response, throwsA(TypeMatcher<ArgumentError>()));
      });

      test('returns plain response data', () async {
        final url = '$baseUrl/getText';
        final response = await ardriveNetwork.get(url: url);

        expect(response.data, 'ok');
        expect(response.retryAttempts, 0);
      });

      test('returns decoded json response', () async {
        final url = '$baseUrl/getJson';

        final getResponse = await ardriveNetwork.get(url: url, isJson: true);

        expect(getResponse.data['message'], 'ok');
        expect(getResponse.retryAttempts, 0);

        final getJsonResponse = await ardriveNetwork.getJson(url);

        expect(getJsonResponse.data['message'], 'ok');
        expect(getJsonResponse.retryAttempts, 0);
      });

      test('returns byte response', () async {
        final url = '$baseUrl/getText';

        final getResponse = await ardriveNetwork.get(url: url, asBytes: true);

        expect(getResponse.data, Uint8List.fromList([111, 107]));
        expect(getResponse.retryAttempts, 0);

        final getAsBytesResponse = await ardriveNetwork.getAsBytes(url);

        expect(getAsBytesResponse.data, Uint8List.fromList([111, 107]));
        expect(getAsBytesResponse.retryAttempts, 0);
      });

      test('fail without retry', () async {
        final url = '$baseUrl/404';

        await expectLater(
            () => ardriveNetwork.get(url: url),
            throwsA(ArDriveNetworkException(
              retryAttempts: 0,
              dioException: {},
            )));
      });

      retryStatusCodes.forEach((statusCode) {
        test('retry 8 times by default when response is $statusCode', () async {
          final url = '$baseUrl/$statusCode';

          await expectLater(
              () => ardriveNetwork.get(url: url),
              throwsA(ArDriveNetworkException(
                retryAttempts: 8,
                dioException: {},
              )));
        });
      });

      test('retry 4 times', () async {
        final ardriveNetwork = ArdriveNetwork(
          retries: 4,
          retryDelayMs: 0,
          noLogs: true,
        );
        final url = '$baseUrl/429';

        await expectLater(
            () => ardriveNetwork.get(url: url),
            throwsA(ArDriveNetworkException(
              retryAttempts: 4,
              dioException: {},
            )));
      });
    });
  });
}
