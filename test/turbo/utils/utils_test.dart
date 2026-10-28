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

  group('convertWinstonToCostString', () {
    test('rounds a cost to 4 decimal places', () {
      // The 300 KB upload the dialog quoted as 0.007935750989 AR.
      expect(convertWinstonToCostString(BigInt.from(7935750989)), '0.0079');
      expect(convertWinstonToCostString(BigInt.from(1891629430804)), '1.8916');
    });

    test('shows a cost too small for 4 decimals as < 0.0001, not zero', () {
      expect(convertWinstonToCostString(BigInt.from(99999999)), '< 0.0001');
      expect(convertWinstonToCostString(BigInt.one), '< 0.0001');
      expect(convertWinstonToCostString(BigInt.from(100000000)), '0.0001');
    });

    test('shows a free upload as 0.0000', () {
      expect(convertWinstonToCostString(BigInt.zero), '0.0000');
    });
  });

  group('convertWinstonToAR', () {
    test('converts winston to AR as double', () {
      expect(convertWinstonToAr(BigInt.from(5000000000000)), 5.0);
      expect(convertWinstonToAr(BigInt.from(1234567890000)), 1.23456789);
      expect(convertWinstonToAr(BigInt.from(0)), 0.0);
    });
  });

  /// Credits read the same everywhere in the top-up: 4 decimal places and a
  /// lowercase unit. Balances of 1 or more showed 2 places, and tiny ones 6.
  group('formatCreditsFromWinc', () {
    test('always shows 4 decimal places', () {
      expect(formatCreditsFromWinc(BigInt.from(13451500000000)),
          '13.4515 credits');
      expect(
          formatCreditsFromWinc(BigInt.from(942400000000)), '0.9424 credits');
      expect(formatCreditsFromWinc(BigInt.zero), '0.0000 credits');
    });
  });
}
