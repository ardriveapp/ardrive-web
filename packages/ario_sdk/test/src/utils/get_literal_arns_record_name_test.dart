import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('getLiteralARNSRecordName', () {
    test('returns the correct record name for a given ARNSUndername', () {
      // Arrange
      const undername = ARNSUndername(
        name: 'test',
        domain: 'example.com',
        record: ARNSRecord(
          transactionId: '123',
          ttlSeconds: 100,
        ),
      );

      // Act
      final result = getLiteralARNSRecordName(undername);

      // Assert
      expect(result, 'test_example.com');
    });

    test('returns the correct record name for a given ARNSUndername with @',
        () {
      // Arrange
      const undername = ARNSUndername(
        name: '@', // @ is the default name for the root domain
        domain: 'example.com',
        record: ARNSRecord(
          transactionId: '123',
          ttlSeconds: 100,
        ),
      );

      // Act
      final result = getLiteralARNSRecordName(undername);

      // Assert
      expect(result, 'example.com');
    });
  });
}
