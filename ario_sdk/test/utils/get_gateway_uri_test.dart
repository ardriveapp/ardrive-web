import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSettings extends Mock implements Settings {}

class MockGateway extends Mock implements Gateway {}

void main() {
  group('getGatewayUri', () {
    test('should return correct Uri', () {
      final mockSettings = MockSettings();
      when(() => mockSettings.protocol).thenReturn('https');
      when(() => mockSettings.fqdn).thenReturn('example.com');
      when(() => mockSettings.port).thenReturn(443);

      final mockGateway = MockGateway();
      when(() => mockGateway.settings).thenReturn(mockSettings);

      final uri = getGatewayUri(mockGateway);

      expect(uri, Uri(scheme: 'https', host: 'example.com', port: 443));
    });
  });
}
