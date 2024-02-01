import 'package:ardrive/turbo/utils/utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('convertWinstonToAr method', () {
    test('should return 0.0001 when winston is 100000000', () {
      final result = convertWinstonToAr(BigInt.from(100000000));
      expect(result, 0.0001);
    });
  });

  group('convertCreditsToLiteralString method', () {
    test('should return 0.0001 when credits is 100000000', () {
      final result = convertWinstonToLiteralString(BigInt.from(100000000));
      expect(result, '0.0001');
    });
  });
}
