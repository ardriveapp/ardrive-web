import 'package:ardrive/turbo/utils/utils.dart';
import 'package:test/test.dart';

void main() {
  group('convertWinstonToLiteralString', () {
    test('returns correct literal credits string', () {
      expect(
          convertWinstonToLiteralString(BigInt.from(5000000000000)), '5.0000');
      expect(
          convertWinstonToLiteralString(BigInt.from(1234567890000)), '1.2346');
      expect(convertWinstonToLiteralString(BigInt.from(0)), '0.0000');
    });
  });

  group('convertWinstonToAR', () {
    test('converts winston to AR as double', () {
      expect(convertWinstonToAr(BigInt.from(5000000000000)), 5.0);
      expect(convertWinstonToAr(BigInt.from(1234567890000)), 1.23456789);
      expect(convertWinstonToAr(BigInt.from(0)), 0.0);
    });
  });
}
