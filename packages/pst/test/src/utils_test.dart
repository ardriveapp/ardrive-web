import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pst/src/utils.dart';

void main() {
  group('weightedRandom', () {
    final Map<ArweaveAddress, double> mockInput = {
      ArweaveAddress('MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM'): .1,
      ArweaveAddress('NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN'): .2,
      ArweaveAddress('OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO'): .3,
    };
    const double randomA = .2;
    const double randomB = .9;

    test('returns a random address within the input', () {
      final tokenHolderAddr = weightedRandom(mockInput, testingRandom: randomA);
      expect(
        tokenHolderAddr,
        ArweaveAddress('NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN'),
      );
    });

    test('returns null if the address could not be determined', () {
      final tokenHolderAddr = weightedRandom(mockInput, testingRandom: randomB);
      expect(
        tokenHolderAddr,
        null,
      );
    });
  });
}
