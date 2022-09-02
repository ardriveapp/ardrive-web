import 'package:ardrive/pst/utils.dart';
import 'package:ardrive/types/arweave_address.dart';
import 'package:test/test.dart';

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
