import 'package:ardrive_network/ardrive_network.dart';
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

    test('return decoded json response', () async {
      final url = '$baseUrl/getJson';
      final response = await ardriveNetwork.getJson(url);

      expect(response.data['message'], 'ok');
      expect(response.retryAttempts, 0);
    });

    test('it should fail without retry', () async {
      final url = '$baseUrl/404';

      await expectLater(
          () => ardriveNetwork.getJson(url),
          throwsA(ArDriveNetworkException(
            retryAttempts: 0,
            dioException: {},
          )));
    });

    retryStatusCodes.forEach((statusCode) {
      test('it should retry 8 times by default when response is $statusCode',
          () async {
        final url = '$baseUrl/$statusCode';

        await expectLater(
            () => ardriveNetwork.getJson(url),
            throwsA(ArDriveNetworkException(
              retryAttempts: 8,
              dioException: {},
            )));
      });
    });

    test('it should retry 4 times', () async {
      final ardriveNetwork = ArdriveNetwork(
        retries: 4,
        retryDelayMs: 0,
        noLogs: true,
      );
      final url = '$baseUrl/429';

      await expectLater(
          () => ardriveNetwork.getJson(url),
          throwsA(ArDriveNetworkException(
            retryAttempts: 4,
            dioException: {},
          )));
    });
  });
}
