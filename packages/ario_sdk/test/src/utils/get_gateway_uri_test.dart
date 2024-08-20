import 'package:ario_sdk/ario_sdk.dart'; // Import the ario_sdk package.
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('getGatewayUri', () {
    test('returns correct URI for standard input', () {
      final settings = Settings(
        protocol: 'https',
        fqdn: 'example.com',
        port: 443,
        allowDelegatedStaking: true,
        delegateRewardShareRatio: 50,
        properties: 'some properties',
        note: 'some note',
        minDelegatedStake: 500,
        label: '',
        autoStake: false,
      );
      final gateway = Gateway(
        settings: settings,
        gatewayAddress: 'gatewayAddress',
        observerAddress: 'observerAddress',
        operatorStake: 1000,
        startTimestamp: 1622519735,
        endTimestamp: 1622529735,
        totalDelegatedStake: 2000,
        stats: Stats(
          failedConsecutiveEpochs: 1,
          observedEpochCount: 10,
          passedConsecutiveEpochs: 5,
          totalEpochCount: 20,
          prescribedEpochCount: 15,
          passedEpochCount: 15,
          failedEpochCount: 5,
        ),
        status: 'active',
      );

      final uri = getGatewayUri(gateway);
      expect(
        '${uri.scheme}://${uri.host}:${uri.port}',
        'https://example.com:443',
      );
    });

    test('returns correct URI for non-standard port', () {
      final settings = Settings(
        protocol: 'https',
        fqdn: 'example.com',
        port: 8080,
        allowDelegatedStaking: true,
        delegateRewardShareRatio: 50,
        properties: 'some properties',
        note: 'some note',
        minDelegatedStake: 500,
        label: '',
        autoStake: false,
      );
      final gateway = Gateway(
        settings: settings,
        gatewayAddress: 'gatewayAddress',
        observerAddress: 'observerAddress',
        operatorStake: 1000,
        startTimestamp: 1622519735,
        endTimestamp: 1622529735,
        totalDelegatedStake: 2000,
        stats: Stats(
          failedConsecutiveEpochs: 1,
          observedEpochCount: 10,
          passedConsecutiveEpochs: 5,
          totalEpochCount: 20,
          prescribedEpochCount: 15,
          passedEpochCount: 15,
          failedEpochCount: 5,
        ),
        status: 'active',
      );

      final uri = getGatewayUri(gateway);
      expect(
        '${uri.scheme}://${uri.host}:${uri.port}',
        'https://example.com:8080',
      );
    });

    test('returns correct URI when FQDN is an IP address', () {
      final settings = Settings(
        protocol: 'http',
        fqdn: '192.168.1.1',
        port: 80,
        allowDelegatedStaking: true,
        delegateRewardShareRatio: 50,
        properties: 'some properties',
        note: 'some note',
        minDelegatedStake: 500,
        label: '',
        autoStake: false,
      );

      final gateway = Gateway(
        settings: settings,
        gatewayAddress: 'gatewayAddress',
        observerAddress: 'observerAddress',
        operatorStake: 1000,
        startTimestamp: 1622519735,
        endTimestamp: 1622529735,
        totalDelegatedStake: 2000,
        stats: Stats(
          failedConsecutiveEpochs: 1,
          observedEpochCount: 10,
          passedConsecutiveEpochs: 5,
          totalEpochCount: 20,
          prescribedEpochCount: 15,
          passedEpochCount: 15,
          failedEpochCount: 5,
        ),
        status: 'active',
      );

      final uri = getGatewayUri(gateway);

      expect(
          '${uri.scheme}://${uri.host}:${uri.port}', 'http://192.168.1.1:80');
    });
  });
}
