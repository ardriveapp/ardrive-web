import 'package:ardrive/types/winston.dart';
import 'package:test/test.dart';

void main() {
  group('Winston type', () {
    test('accepts an integer', () {
      final winstonA = Winston(10);
      final winstonB = Winston(0);
      expect(winstonA.asInteger, 10);
      expect(winstonB.asInteger, 0);
    });

    test('equatability', () {
      expect(Winston(10) == Winston(11), false);
      expect(Winston(10) == Winston(10), true);
    });

    test('throws if the amount is less than zero', () {
      expect(
        () => Winston(-1),
        throwsA(const TypeMatcher<InvalidWinstonValue>()),
      );
    });

    test('plus function', () {
      final winstonA = Winston(10);
      final winstonB = Winston(20);
      expect(winstonA.plus(winstonB).asInteger, 30);
    });

    test('minus function', () {
      final winstonA = Winston(10);
      final winstonB = Winston(5);
      expect(winstonA.minus(winstonB).asInteger, 5);
    });

    test('times function', () {
      final winstonA = Winston(10);
      final winstonB = Winston(3);
      expect(winstonA.times(winstonB).asInteger, 30);
    });

    group('dividedBy function', () {
      test('returns the value rounded ceil', () {
        final winstonA = Winston(15);
        final winstonB = Winston(2);
        expect(winstonA.dividedBy(winstonB).asInteger, 8);
        expect(
          winstonA
              .dividedBy(
                winstonB,
                round: RoundStrategy.roundCeil,
              )
              .asInteger,
          8,
        );
      });

      test('returns the value rounded down', () {
        final winstonA = Winston(15);
        final winstonB = Winston(2);
        expect(
          winstonA
              .dividedBy(
                winstonB,
                round: RoundStrategy.roundDown,
              )
              .asInteger,
          7,
        );
      });
    });

    test('isGreaterThan function', () {
      final winstonA = Winston(15);
      final winstonB = Winston(2);
      expect(winstonA.isGreaterThan(winstonB), true);
      expect(winstonB.isGreaterThan(winstonA), false);
      expect(winstonA.isGreaterThan(winstonA), false);
    });

    test('isLessThan function', () {
      final winstonA = Winston(15);
      final winstonB = Winston(2);
      expect(winstonA.isLessThan(winstonB), false);
      expect(winstonB.isLessThan(winstonA), true);
      expect(winstonA.isLessThan(winstonA), false);
    });

    test('toString method', () {
      final winston = Winston(15);
      expect(winston.toString(), '15');
    });

    test('maxWinston function', () {
      final winstonA = Winston(2);
      final winstonB = Winston(1);
      final max = Winston.maxWinston(winstonA, winstonB);
      expect(max, winstonA);
    });
  });
}
