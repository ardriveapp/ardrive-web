import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:flutter_test/flutter_test.dart';

BigInt _winc(String credits) {
  final parts = credits.split('.');
  final fraction = (parts.length > 1 ? parts[1] : '').padRight(12, '0');
  return BigInt.parse(parts[0]) * BigInt.from(10).pow(12) +
      BigInt.parse(fraction);
}

void main() {
  group('formatArNSCredits', () {
    // Removing an undername on devnet: 0.001 for the record and 0.000061
    // for the metadata update. The cost line said 0.0010, less than the
    // 0.001061 debited.
    test('rounds up, so the cost is never shown lower than it is', () {
      expect(formatArNSCredits(_winc('0.001061110514')), '0.0011');
      expect(formatArNSCredits(_winc('0.113940940954')), '0.1140');
      expect(formatArNSCredits(_winc('2.713896025703')), '2.72');
    });

    test('keeps an exact amount as it is', () {
      expect(formatArNSCredits(_winc('0.001')), '0.0010');
      expect(formatArNSCredits(_winc('2.5')), '2.50');
    });

    test('just under one credit reads as one', () {
      expect(formatArNSCredits(_winc('0.99999')), '1.00');
    });

    test('is never free and never zero when it is not', () {
      expect(formatArNSCredits(BigInt.zero), '0');
      expect(formatArNSCredits(BigInt.one), '< 0.0001');
      expect(formatArNSCredits(_winc('0.0001')), '0.0001');
    });
  });
}
