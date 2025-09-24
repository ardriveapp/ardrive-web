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
}
