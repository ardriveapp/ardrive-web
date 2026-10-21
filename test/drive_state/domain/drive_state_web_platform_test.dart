import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
import 'package:test/test.dart';

/// The one claim in `drive_state` that was argued *from* a platform
/// difference, executed on both platforms it names.
///
/// Every other test in this repository runs on the Dart VM, and ArDrive's
/// primary platform is a browser. Most of `test/drive_state` cannot close that
/// gap: the export, import, sync-source, creation-service and cubit tests all
/// reach a Drift database, and `sqlite3`'s FFI implementation does not compile
/// to JavaScript at all — `flutter test test/drive_state --platform chrome`
/// dies in the compiler on `dart:ffi` types before a single test runs.
///
/// This file is deliberately narrow so that it can be the exception: pure Dart,
/// one import, no database, no Flutter binding, no `dart:io`. It runs unchanged
/// under
///
/// ```
/// flutter test test/drive_state/domain/drive_state_web_platform_test.dart \
///   --platform chrome
/// ```
///
/// as well as in the default VM run, and it is written so that every
/// expectation holds on both — a test that could only pass on one would be the
/// bug it is looking for.
void main() {
  group('DriveStateFormatVersion on whichever platform this is', () {
    /// The shortest run of `9`s this platform's `int` cannot hold and print
    /// back unchanged.
    ///
    /// Measured rather than assumed, because the measurement is the whole
    /// point. On the VM it is 19: an `int` is 64-bit, `9999999999999999999`
    /// is past `2^63 - 1`, and `int.parse` throws rather than wrap. Compiled
    /// to JavaScript an `int` is a double, and it is 16: `int.parse` returns
    /// `10000000000000000` for `'9999999999999999'` — silently, with no
    /// exception for a caller to catch and no way to tell afterwards that the
    /// value it is comparing is not the value that was written.
    ///
    /// Both numbers were observed under this repository's own toolchain, not
    /// read off a spec.
    int firstLengthThisPlatformCannotHold() {
      for (var digits = 1; digits <= 40; digits++) {
        final raw = '9' * digits;
        try {
          if (int.parse(raw).toString() != raw) return digits;
        } on FormatException {
          return digits;
        }
      }
      return 41;
    }

    /// The longest component the type will actually admit — discovered by
    /// asking it, not restated from its regex, so that widening the regex
    /// moves this number and the assertions below notice.
    int longestComponentTheTypeAdmits() {
      for (var digits = 1; digits <= 40; digits++) {
        if (DriveStateFormatVersion.tryParse('${'9' * digits}.0') == null) {
          return digits - 1;
        }
      }
      return 40;
    }

    test('the cap is nine digits', () {
      expect(longestComponentTheTypeAdmits(), 9);
    });

    test('the cap is inside what this platform can hold', () {
      // The real invariant, and the reason this file runs twice: the cap has
      // to sit below the *smaller* of the two platform limits, and only a run
      // on the platform in question can prove it sits below that one's. On
      // the VM this proves 9 < 19. On chrome it proves 9 < 16 — which is the
      // half that had only ever been reasoned about.
      //
      // It is also the assertion with teeth. Widen the pattern to seventeen
      // digits and the VM still passes this, because 17 < 19; chrome fails,
      // because 17 > 16. A cap chosen against one platform's `int` is exactly
      // the bug it catches.
      expect(
        longestComponentTheTypeAdmits(),
        lessThan(firstLengthThisPlatformCannotHold()),
        reason: 'a component the pattern admits but this platform cannot hold '
            'exactly would compare differently depending on where it ran',
      );
    });

    test('the widest version the pattern accepts round-trips and compares', () {
      const widest = '999999999.999999999';
      final version = DriveStateFormatVersion.parse(widest);

      expect(version.major, 999999999);
      expect(version.minor, 999999999);
      // Round-trip, because two clients that print the same version
      // differently are two clients that cannot be told apart in a log.
      expect(version.toString(), widest);
      // And ordering, because a version is only ever held in order to be
      // compared, and a double that has run out of mantissa compares equal to
      // its neighbour instead of greater than it.
      expect(
        version > const DriveStateFormatVersion(999999999, 999999998),
        isTrue,
      );
      expect(version < const DriveStateFormatVersion(1000000000, 0), isTrue);
    });

    test('a tenth digit is refused identically on both platforms', () {
      // Ten digits is exact on the VM *and* in a browser — this is the cap
      // being conservative rather than either platform failing, and the
      // refusal comes from the pattern, not from arithmetic. Worth pinning on
      // both: a regex is the one thing here that could not diverge, so if
      // these ever disagree the divergence is somewhere nobody is looking.
      expect(DriveStateFormatVersion.tryParse('1000000000.0'), isNull);
      expect(DriveStateFormatVersion.tryParse('0.1000000000'), isNull);
      expect(int.parse('1000000000').toString(), '1000000000');
    });

    test('a version past every int is refused before anything parses it', () {
      // The case the cap actually protects against, and the reason `tryParse`
      // must reject on the pattern rather than by catching a parse failure:
      // the VM throws on this string and a browser quietly rounds it, so a
      // `try`/`catch` implementation would return null on one platform and a
      // wrong version on the other.
      expect(
        DriveStateFormatVersion.tryParse('99999999999999999999.0'),
        isNull,
      );
      expect(
        () => DriveStateFormatVersion.parse('99999999999999999999.0'),
        throwsFormatException,
      );
    });
  });
}
