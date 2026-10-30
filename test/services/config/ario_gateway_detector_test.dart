import 'package:ardrive/services/config/ario_gateway_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArIOGatewayDetector', () {
    test('detectArIOGateway returns null on non-web platforms', () async {
      // This test runs on VM (non-web), so it should return null
      final result = await ArIOGatewayDetector.detectArIOGateway();

      expect(result, isNull);
    });
  });

  group('the domains asked whether they are a gateway', () {
    List<String> candidates(String host, {bool alsoTryHost = false}) =>
        ArIOGatewayDetector.candidateGateways(host, alsoTryHost: alsoTryHost);

    test('the domain above the host', () {
      expect(candidates('ardrive.ar.io'), ['ar.io']);
      expect(candidates('ardrive.turbo-gateway.com'), ['turbo-gateway.com']);
    });

    test('never a top-level domain or localhost', () {
      expect(candidates('turbo-gateway.com'), isEmpty);
      expect(candidates('localhost'), isEmpty);
    });

    test('never the "domain" of an IP address', () {
      expect(candidates('127.0.0.1'), isEmpty);
      expect(candidates('192.168.1.20'), isEmpty);
      expect(candidates('::1'), isEmpty);
      expect(candidates('127.0.0.1', alsoTryHost: true), ['127.0.0.1'],
          reason: 'a gateway can be served from an address');
    });

    // ardrive.io 404s, and asking it held up every first visit to the app.
    test("never ArDrive's own domain", () {
      expect(candidates('app.ardrive.io'), isEmpty);
      expect(candidates('staging.ardrive.io'), isEmpty);
      expect(candidates('ardrive.io', alsoTryHost: true), isEmpty);
    });

    test('a publication also asks its own host', () {
      expect(
          candidates('abc.ar.io', alsoTryHost: true), ['ar.io', 'abc.ar.io']);
      expect(candidates('publication.ardrive.io', alsoTryHost: true),
          ['publication.ardrive.io']);
    });
  });
}
