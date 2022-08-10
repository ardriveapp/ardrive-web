import 'package:ardrive/types/winston.dart';
import 'package:test/test.dart';

void main() {
  group('Winston type', () {
    test('accepts an integer', () {
      final winstonA = Winston(BigInt.from(10));
      final winstonB = Winston(BigInt.zero);
      expect(winstonA.value, BigInt.from(10));
      expect(winstonB.value, BigInt.zero);
    });

    test('equatability', () {
      expect(Winston(BigInt.from(10)) == Winston(BigInt.from(11)), false);
      expect(Winston(BigInt.from(10)) == Winston(BigInt.from(10)), true);
    });

    test('throws if the amount is less than zero', () {
      expect(
        () => Winston(BigInt.from(-1)),
        throwsA(const TypeMatcher<InvalidWinstonValue>()),
      );
    });

    test('plus function', () {
      final winstonA = Winston(BigInt.from(10));
      final winstonB = Winston(BigInt.from(20));
      expect(winstonA.plus(winstonB).value, BigInt.from(30));
    });

    test('minus function', () {
      final winstonA = Winston(BigInt.from(10));
      final winstonB = Winston(BigInt.from(5));
      expect(winstonA.minus(winstonB).value, BigInt.from(5));
    });

    test('times function', () {
      final winstonA = Winston(BigInt.from(10));
      final winstonB = Winston(BigInt.from(3));
      expect(winstonA.times(winstonB).value, BigInt.from(30));
    });

    group('dividedBy function', () {
      test('returns the value rounded ceil', () {
        final winstonA = Winston(BigInt.from(15));
        final winstonB = Winston(BigInt.from(2));
        expect(winstonA.dividedBy(winstonB).value, BigInt.from(8));
        expect(
          winstonA
              .dividedBy(
                winstonB,
                round: RoundStrategy.roundCeil,
              )
              .value,
          BigInt.from(8),
        );
      });

      test('returns the value rounded down', () {
        final winstonA = Winston(BigInt.from(15));
        final winstonB = Winston(BigInt.from(2));
        expect(
          winstonA
              .dividedBy(
                winstonB,
                round: RoundStrategy.roundDown,
              )
              .value,
          BigInt.from(7),
        );
      });
    });

    test('isGreaterThan function', () {
      final winstonA = Winston(BigInt.from(15));
      final winstonB = Winston(BigInt.from(2));
      expect(winstonA.isGreaterThan(winstonB), true);
      expect(winstonB.isGreaterThan(winstonA), false);
      expect(winstonA.isGreaterThan(winstonA), false);
    });

    test('isLessThan function', () {
      final winstonA = Winston(BigInt.from(15));
      final winstonB = Winston(BigInt.from(2));
      expect(winstonA.isLessThan(winstonB), false);
      expect(winstonB.isLessThan(winstonA), true);
      expect(winstonA.isLessThan(winstonA), false);
    });

    test('toString method', () {
      final winston = Winston(BigInt.from(15));
      expect(winston.toString(), '15');
    });

    test('maxWinston function', () {
      final winstonA = Winston(BigInt.from(2));
      final winstonB = Winston(BigInt.from(1));
      final max = Winston.maxWinston(winstonA, winstonB);
      expect(max, winstonA);
    });
  });
}
