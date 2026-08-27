import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
import 'package:test/test.dart';

void main() {
  _bothRegimes();
  group('DriveStateFormatVersion', () {
    test('this build writes 0.1 — an experiment, not a commitment', () {
      // 0.x is deliberate. Nothing published under a zero major is a format
      // anyone has committed to, and a later reader refuses it by the ordinary
      // rule rather than by a special case. The bump to 1.0 is the moment this
      // stops being an experiment and should be its own decision.
      expect(DriveStateFormatVersion.current.major, 0);
      expect(DriveStateFormatVersion.current.minor, 1);
      expect(DriveStateFormatVersion.current.toString(), '0.1');
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
          // More digits than the nine-digit cap admits. Ten is still exact on
          // both the VM and a browser — the cap sits deliberately below where
          // they stop agreeing, which is sixteen digits. See
          // drive_state_web_platform_test.dart, which measures that.
          '1000000000.0',
          '0.1000000000',
          // And one no platform holds the same way: the VM's `int.parse`
          // throws on it, a browser's rounds it.
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
      test('accepts only its exact version while the major is 0', () {
        // The additive-minor rule is suspended in the 0.x range: an unknown
        // minor is a different format, not an extension of this one. The
        // above-1.0 behaviour is covered by `readableBy` below, which names
        // its reader and so can test both regimes.
        for (final minor in [0, 2, 9, 10, 999999999]) {
          final version = DriveStateFormatVersion(
            DriveStateFormatVersion.current.major,
            minor,
          );

          expect(version.isReadableByThisBuild, isFalse);
          // And each one still reports a direction, so there is always an arm
          // to explain the refusal with.
          expect(
            version.isNewerThanThisBuild || version.isOlderThanThisBuild,
            isTrue,
          );
        }
      });

      test('refuses a higher major', () {
        const version = DriveStateFormatVersion(2, 0);

        expect(version.isReadableByThisBuild, isFalse);
        expect(version.isNewerThanThisBuild, isTrue);
        expect(version.isOlderThanThisBuild, isFalse);
      });

      test('refuses an older version, and says which it was', () {
        // Two separate questions rather than one "unreadable" flag, because
        // the two directions need two different sentences: one says this
        // client is behind, the other says the artifact is.
        //
        // While `current` is 0.1 the only older version expressible is 0.0 —
        // the comparison is on the minor here, which is what makes 0.x strict.
        const version = DriveStateFormatVersion(0, 0);

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

void _bothRegimes() {
  // `readableBy` names its reader instead of reading the constant, so both
  // sides of the rule can be tested no matter where `current` happens to sit.
  group('the compatibility rule, in both regimes', () {
    const v = DriveStateFormatVersion.new;

    group('above 1.0 the major is the unit — a minor is additive', () {
      const reader = DriveStateFormatVersion(1, 2);

      test('any minor within the reader major is readable', () {
        expect(v(1, 0).readableBy(reader), isTrue);
        expect(v(1, 2).readableBy(reader), isTrue);
        expect(v(1, 7).readableBy(reader), isTrue,
            reason: 'a minor this reader has never heard of is additive');
      });

      test('another major is not, and says which direction', () {
        expect(v(2, 0).readableBy(reader), isFalse);
        expect(v(2, 0).newerThan(reader), isTrue);
        expect(v(0, 9).readableBy(reader), isFalse);
        expect(v(0, 9).olderThan(reader), isTrue);
      });
    });

    group('in 0.x the minor is the unit — nothing is additive yet', () {
      const reader = DriveStateFormatVersion(0, 1);

      test('only the exact version is readable', () {
        expect(v(0, 1).readableBy(reader), isTrue);
        expect(v(0, 2).readableBy(reader), isFalse,
            reason: '0.x is unsettled: 0.2 may mean what 0.1 would misread');
        expect(v(0, 0).readableBy(reader), isFalse);
      });

      test('every unreadable version still has a direction to report', () {
        // The failure §6.1 is about, from the other end: a version that is
        // neither readable nor newer nor older has no arm to report, and the
        // reader falls back to complaining about the payload's shape.
        for (final other in [v(0, 0), v(0, 2), v(0, 9), v(1, 0), v(9, 9)]) {
          if (other.readableBy(reader)) continue;
          expect(
            other.newerThan(reader) || other.olderThan(reader),
            isTrue,
            reason: '$other is unreadable but reports neither direction',
          );
        }
      });
    });
  });
}
