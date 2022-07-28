import 'package:ardrive/utils/compare_alphabetically_and_natural.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('test compareAlphabeticallyAndNatural function', () {
    test(
        'should return -1 when the letter `a` lower case is before `B` upper case',
        () {
      expect(compareAlphabeticallyAndNatural('a', 'B'), -1);
    });

    test('should return 1 when `B` upper case is after `a` lower case', () {
      expect(compareAlphabeticallyAndNatural('a', 'B'), -1);
    });

    test('should return 1 when 100 is after 99', () {
      expect(compareAlphabeticallyAndNatural('100', '99'), 1);
    });

    test('should return -1 when 10a is before 99a', () {
      expect(compareAlphabeticallyAndNatural('10a', '99a'), -1);
    });

    test('should return -1 when 1a1 is before 9a9', () {
      expect(compareAlphabeticallyAndNatural('10a', '99a'), -1);
    });

    test('should return -1 when aaaa1 is before aaaa2', () {
      expect(compareAlphabeticallyAndNatural('10a', '99a'), -1);
    });
    test('should return 0 when both strings are equal', () {
      expect(compareAlphabeticallyAndNatural('A', 'A'), 0);
    });

    test(
        'should return 0 when both strings are the same letter regarless if its upper case',
        () {
      expect(compareAlphabeticallyAndNatural('A', 'a'), 0);
    });
  });
}
