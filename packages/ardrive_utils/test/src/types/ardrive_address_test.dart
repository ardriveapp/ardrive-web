import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArweaveAddress type', () {
    const validAddr = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    const anotherValidAddr = 'BAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    const invalidAddr = 'an invalid ADDRESS value';

    test('accepts a valid address', () {
      final addr = ArweaveAddress(validAddr);
      expect(addr.toString(), validAddr);
    });

    test('throws if an invalid address is passed', () {
      expect(
        () => ArweaveAddress(invalidAddr),
        throwsA(const TypeMatcher<InvalidAddress>()),
      );
    });

    test('equality', () {
      expect(ArweaveAddress(validAddr) == ArweaveAddress(validAddr), true);
      expect(
        ArweaveAddress(validAddr) == ArweaveAddress(anotherValidAddr),
        false,
      );
    });
  });
}
