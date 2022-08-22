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
      final valueA = BigInt.from(10);
      final valueB = BigInt.from(11);
      expect(Winston(valueA) == Winston(valueB), false);
      expect(Winston(valueA) == Winston(valueA), true);
    });

    test('throws if the amount is less than zero', () {
      expect(
        () => Winston(BigInt.from(-1)),
        throwsA(const TypeMatcher<InvalidWinstonValue>()),
      );
    });

    test('operator +', () {
      final winstonA = Winston(BigInt.from(10));
      final winstonB = Winston(BigInt.from(20));
      expect((winstonA + winstonB).value, BigInt.from(30));
    });

    test('operator -', () {
      final winstonA = Winston(BigInt.from(10));
      final winstonB = Winston(BigInt.from(5));
      expect((winstonA - winstonB).value, BigInt.from(5));
    });

    test('operator *', () {
      final winstonA = Winston(BigInt.from(10));
      final winstonB = Winston(BigInt.from(3));
      expect((winstonA * winstonB).value, BigInt.from(30));
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

    test('operator >', () {
      final winstonA = Winston(BigInt.from(15));
      final winstonB = Winston(BigInt.from(2));
      expect(winstonA > winstonB, true);
      expect(winstonB > winstonA, false);
      expect(winstonA > winstonA, false);
    });

    test('operator <', () {
      final winstonA = Winston(BigInt.from(15));
      final winstonB = Winston(BigInt.from(2));
      expect(winstonA < winstonB, false);
      expect(winstonB < winstonA, true);
      expect(winstonA < winstonA, false);
    });

    test('toString method', () {
      final winston = Winston(BigInt.from(15));
      expect(winston.toString(), '15');
      expect('$winston', '15');
    });

    test('maxWinston function', () {
      final winstonA = Winston(BigInt.from(2));
      final winstonB = Winston(BigInt.from(1));
      final max = Winston.maxWinston(winstonA, winstonB);
      expect(max, winstonA);
    });
  });
}
