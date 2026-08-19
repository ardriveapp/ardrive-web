import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
import 'package:test/test.dart';

void main() {
  group('DriveStateFormatVersion', () {
    test('this build writes 1.0', () {
      expect(DriveStateFormatVersion.current.major, 1);
      expect(DriveStateFormatVersion.current.minor, 0);
      expect(DriveStateFormatVersion.current.toString(), '1.0');
    });

    group('tryParse', () {
      test('reads a major.minor pair', () {
        expect(
          DriveStateFormatVersion.tryParse('1.0'),
          const DriveStateFormatVersion(1, 0),
        );
        expect(
          DriveStateFormatVersion.tryParse('0.15'),
          const DriveStateFormatVersion(0, 15),
        );
        expect(
          DriveStateFormatVersion.tryParse('12.345'),
          const DriveStateFormatVersion(12, 345),
        );
      });

      test('round-trips every version it accepts', () {
        // The property the whole type exists to have: two clients holding the
        // same version print the same string, and the string they print parses
        // back to the version they hold. Without it, `1.0` and `01.0` compare
        // equal while reading differently in a log.
        for (final raw in ['0.0', '1.0', '1.10', '9.99', '999999999.0']) {
          expect(DriveStateFormatVersion.tryParse(raw)!.toString(), raw);
        }
      });

      test('refuses a version it cannot compare', () {
        for (final raw in [
          // The bare integer this format used to carry. Refused deliberately:
          // no writer emits it, so accepting it would be a compatibility path
          // with nothing on the other end of it.
          '1',
          '1.0.0',
          '1.0.',
          '.1',
          'x.y',
          '1.x',
          '1.-1',
          '-1.0',
          '+1.0',
          '',
          ' ',
          '1.0 ',
          ' 1.0',
          '1. 0',
          '1,0',
          // Leading zeros: they would parse to a value that prints back
          // differently.
          '01.0',
          '1.00',
          '1.01',
          // Longer than an int is identical on both the VM and a browser.
          '1000000000.0',
          '0.1000000000',
          '99999999999999999999.0',
          '1.0\n',
          'v1.0',
          '1.0-beta',
        ]) {
          expect(
            DriveStateFormatVersion.tryParse(raw),
            isNull,
            reason: '"$raw" is not a major.minor version',
          );
        }
      });

      test('reads an absent version as no version', () {
        expect(DriveStateFormatVersion.tryParse(null), isNull);
      });
    });

    group('parse', () {
      test('returns what tryParse would', () {
        expect(
          DriveStateFormatVersion.parse('2.13'),
          const DriveStateFormatVersion(2, 13),
        );
      });

      test('throws on anything tryParse refuses', () {
        expect(
          () => DriveStateFormatVersion.parse('1'),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('comparison', () {
      test('orders by major first, then minor numerically', () {
        // The failure a string comparison hands you for free: "1.10" sorts
        // below "1.9" lexicographically, and above it in every sense that
        // matters.
        expect(
          const DriveStateFormatVersion(1, 10)
              .compareTo(const DriveStateFormatVersion(1, 9)),
          greaterThan(0),
        );
        expect(
          const DriveStateFormatVersion(1, 10) >
              const DriveStateFormatVersion(1, 9),
          isTrue,
        );
        expect('1.10'.compareTo('1.9'), lessThan(0));

        expect(
          const DriveStateFormatVersion(2, 0) >
              const DriveStateFormatVersion(1, 99),
          isTrue,
        );
        expect(
          const DriveStateFormatVersion(1, 0) <
              const DriveStateFormatVersion(1, 1),
          isTrue,
        );
        expect(
          const DriveStateFormatVersion(1, 0) <=
              const DriveStateFormatVersion(1, 0),
          isTrue,
        );
        expect(
          const DriveStateFormatVersion(1, 0) >=
              const DriveStateFormatVersion(1, 0),
          isTrue,
        );
      });

      test('sorts a list the way a reader would order artifacts', () {
        final versions = [
          const DriveStateFormatVersion(1, 9),
          const DriveStateFormatVersion(2, 0),
          const DriveStateFormatVersion(1, 10),
          const DriveStateFormatVersion(0, 15),
        ]..sort();

        expect(versions.map((v) => v.toString()).toList(), [
          '0.15',
          '1.9',
          '1.10',
          '2.0',
        ]);
      });

      test('equality is by value, not identity', () {
        expect(
          const DriveStateFormatVersion(1, 0),
          DriveStateFormatVersion.tryParse('1.0'),
        );
        expect(
          const DriveStateFormatVersion(1, 0).hashCode,
          const DriveStateFormatVersion(1, 0).hashCode,
        );
        expect(
          const DriveStateFormatVersion(1, 0),
          isNot(const DriveStateFormatVersion(1, 1)),
        );
      });
    });

    group('the reader rule', () {
      test("accepts every minor of this build's major", () {
        // Only upwards is expressible while `current` is x.0, but the rule is
        // symmetric: the comparison is on the major and the minor is not
        // consulted at all.
        for (final minor in [0, 1, 9, 10, 999999999]) {
          final version = DriveStateFormatVersion(
            DriveStateFormatVersion.current.major,
            minor,
          );

          expect(version.isReadableByThisBuild, isTrue);
          expect(version.isNewerThanThisBuild, isFalse);
          expect(version.isOlderThanThisBuild, isFalse);
        }
      });

      test('refuses a higher major', () {
        const version = DriveStateFormatVersion(2, 0);

        expect(version.isReadableByThisBuild, isFalse);
        expect(version.isNewerThanThisBuild, isTrue);
        expect(version.isOlderThanThisBuild, isFalse);
      });

      test('refuses a lower major, and says which it was', () {
        // Two separate questions rather than one "unreadable" flag, because
        // the two directions need two different sentences: one says this
        // client is behind, the other says the artifact is.
        const version = DriveStateFormatVersion(0, 9);

        expect(version.isReadableByThisBuild, isFalse);
        expect(version.isOlderThanThisBuild, isTrue);
        expect(version.isNewerThanThisBuild, isFalse);
      });

      test('a higher minor of a higher major is still just newer', () {
        // The minor never rescues a major. `2.0` and `2.99` are equally
        // unreadable to a 1.x build.
        for (final minor in [0, 99]) {
          final version = DriveStateFormatVersion(2, minor);

          expect(version.isNewerThanThisBuild, isTrue);
          expect(version.isReadableByThisBuild, isFalse);
        }
      });
    });
  });
}
