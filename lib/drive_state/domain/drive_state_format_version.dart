import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// The drive state artifact's format version: `major.minor`, and nothing else.
///
/// One value, published twice — as the `State-Version` tag (§3.2) and as the
/// payload's top-level `version` field (§3.3) — and parsed back from both. It
/// is a type rather than a pair of ints or a string because it is compared,
/// and both of the obvious shortcuts are wrong in a way that only shows up
/// later: a string compared with `<` orders `"1.10"` below `"1.9"`, and two
/// loose ints let a caller compare the halves in the wrong order or forget the
/// second one.
///
/// ## Why two components and not three
///
/// The version answers exactly one question — *what may a reader assume is in
/// this payload* — and that has two levels, which §6 names:
///
///  * **additive**: a section or a field is added. Older readers ignore what
///    they do not know and use the rest. The **minor** moves.
///  * **breaking**: an older reader would *misinterpret* the payload. The
///    **major** moves, and older readers refuse.
///
/// There is no third level. A patch digit would have to mean "the fields are
/// the same but something else changed", which is not a fact any reader can
/// act on — every reader would ignore it, and a number nobody reads is a
/// number that drifts. Two components also match the protocol this extends:
/// ArFS itself tags `ArFS: "0.15"`.
///
/// ## The reader rule
///
/// **Accept your own major, refuse every other.** Same major, any minor,
/// higher or lower, is readable: unknown sections and fields are ignored, and
/// known sections are still required (§6.1). A different major is refused —
/// and the two directions are refused *separately*, because they are different
/// facts about the world and a reader that blurred them would print the wrong
/// one. See [isNewerThanThisBuild] and [isOlderThanThisBuild].
///
/// ## What is not a version
///
/// [tryParse] accepts `major.minor` and nothing adjacent to it. Not `"1"`, not
/// `"1.0.0"`, not `"x.y"`, not `"1.-1"`, not `"01.0"`, not a number with more
/// digits than an `int` holds identically on every platform this app runs on.
/// All of those are **malformed**, which is a different outcome from
/// "unreadable version": a version that cannot be parsed cannot be compared,
/// so nothing is known about whether this build could have read the payload.
///
/// Tolerating a bare `"1"` as `1.0` was considered and refused. No writer emits
/// that shape — [toString] always writes both components — so accepting it
/// would be a compatibility path with no producer on the other end of it, and
/// the only artifacts it could ever admit are ones built by something that got
/// the format wrong.
@immutable
class DriveStateFormatVersion extends Equatable
    implements Comparable<DriveStateFormatVersion> {
  const DriveStateFormatVersion(this.major, this.minor);

  /// The version this build writes, and the only major it reads.
  ///
  /// Deliberately **one** constant for both the tag and the payload field. Two
  /// constants that must always be equal are two constants that can eventually
  /// differ, and a producer whose tag and payload disagree publishes an
  /// artifact every reader refuses — paid for, permanent, uncorrectable.
  static const DriveStateFormatVersion current = DriveStateFormatVersion(0, 1);

  final int major;
  final int minor;

  /// Exactly `major.minor`, both decimal, neither with a leading zero, each at
  /// most nine digits.
  ///
  /// No leading zeros so that [tryParse] and [toString] are inverses: `"01.0"`
  /// would parse to a value that prints back as `"1.0"`, and a version that
  /// does not round-trip is one that two clients can hold and print
  /// differently while comparing equal.
  ///
  /// Nine digits because an `int` is 64-bit on the VM and a double in a
  /// browser, and this app ships to both.
  ///
  /// The two stop agreeing at **sixteen** digits, where a browser's
  /// `int.parse` starts rounding — `'9999999999999999'` comes back as
  /// `10000000000000000`, silently, with nothing thrown for a caller to catch
  /// — while the VM is still exact; and they disagree again at **nineteen**,
  /// where the VM throws `FormatException` and a browser does not. Which is
  /// also why [tryParse] refuses on the pattern rather than by catching a
  /// parse failure: a `try`/`catch` would return null on one platform and a
  /// wrong version on the other.
  ///
  /// Nine sits well below the nearer of those on purpose. The boundary is
  /// itself a platform fact, so a cap drawn *on* it would be one too, and
  /// ~10^9 format revisions is not a constraint anyone will meet. Both
  /// boundaries are measured, on whichever platform it runs, by
  /// `test/drive_state/domain/drive_state_web_platform_test.dart` — the one
  /// test in `drive_state` that runs under `--platform chrome` as well as on
  /// the VM.
  static final RegExp _pattern =
      RegExp(r'^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$');

  /// The version [raw] names, or null if it does not name one.
  ///
  /// Null-tolerant on purpose: both sources are absent-able — a tag an indexer
  /// never reported, a payload field a producer never wrote — and "absent" and
  /// "unparseable" are the same fact to every caller here, namely that there
  /// is no version to compare.
  static DriveStateFormatVersion? tryParse(String? raw) {
    if (raw == null) return null;

    final match = _pattern.firstMatch(raw);
    if (match == null) return null;

    return DriveStateFormatVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }

  /// [tryParse], for the callers that have already decided an unparseable
  /// version is an exception rather than an outcome — `DriveStateEntity`'s
  /// transaction parsing, which reports every malformed tag the same way.
  static DriveStateFormatVersion parse(String raw) {
    final parsed = tryParse(raw);

    if (parsed == null) {
      throw FormatException(
        'not a major.minor drive state format version',
        raw,
      );
    }

    return parsed;
  }

  /// Whether this build may read a payload written under this version.
  ///
  /// Above `1.0` the major is the compatibility unit: a minor is additive and
  /// optional, so any minor within this build's major is readable.
  ///
  /// **In the `0.x` range the minor is the compatibility unit instead.** `0.x`
  /// says the format is not settled, so `0.2` is free to mean something `0.1`
  /// would misinterpret — exactly as semver treats a zero major. Requiring an
  /// exact match while experimenting is what stops an artifact published from
  /// one staging build being read by a later build that changed the format
  /// underneath it. It is the stricter rule, and strictness is cheap here:
  /// refusing costs one ordinary sync.
  bool get isReadableByThisBuild => readableBy(current);

  /// The rule itself, against an arbitrary reader.
  ///
  /// Takes the reader as a parameter rather than reading [current] so that
  /// both regimes can be tested. With [current] at `0.1`, a test of the
  /// above-1.0 behaviour would otherwise be untestable — and an untested
  /// branch of a compatibility rule is one that stops being true the moment
  /// the constant moves.
  bool readableBy(DriveStateFormatVersion reader) => reader.major == 0
      ? major == 0 && minor == reader.minor
      : major == reader.major;

  /// Newer than [reader], comparing on whichever component is load-bearing so
  /// this stays the exact complement of [readableBy].
  bool newerThan(DriveStateFormatVersion reader) => reader.major == 0
      ? (major > 0 || (major == 0 && minor > reader.minor))
      : major > reader.major;

  /// Older than [reader], on the same terms.
  bool olderThan(DriveStateFormatVersion reader) => reader.major == 0
      ? (major == 0 && minor < reader.minor)
      : major < reader.major;

  /// The artifact was written by a client newer than this one, under a format
  /// that changed something this build would misread.
  ///
  /// Compares on whichever component is load-bearing, so this stays the exact
  /// complement of [isReadableByThisBuild]. In the `0.x` range that is the
  /// minor: `0.9` is newer than `0.1`, and saying "same major, therefore
  /// neither newer nor older" would leave an unreadable artifact with no arm
  /// to report — which is the failure §6.1 is about, met from the other end.
  bool get isNewerThanThisBuild => newerThan(current);

  /// The artifact was written under a format this build has moved past.
  ///
  /// Kept apart from [isNewerThanThisBuild] because the two need different
  /// messages, and because without an explicit arm for it what happens to an
  /// older major depends on the *payload's shape* rather than on its version —
  /// which is the failure §6.1 exists to prevent, read from the other end. One
  /// that genuinely lacks a section is refused saying "payload is missing the
  /// file_revisions section", an accurate sentence that sends the reader
  /// looking for a truncated payload instead of an obsolete one; one that
  /// happens to be structurally compatible is **accepted**, under a format
  /// nobody agreed to.
  bool get isOlderThanThisBuild => olderThan(current);

  @override
  int compareTo(DriveStateFormatVersion other) => major != other.major
      ? major.compareTo(other.major)
      : minor.compareTo(other.minor);

  bool operator <(DriveStateFormatVersion other) => compareTo(other) < 0;
  bool operator <=(DriveStateFormatVersion other) => compareTo(other) <= 0;
  bool operator >(DriveStateFormatVersion other) => compareTo(other) > 0;
  bool operator >=(DriveStateFormatVersion other) => compareTo(other) >= 0;

  @override
  List<Object?> get props => [major, minor];

  /// The wire form, in both places it is written. Round-trips through
  /// [tryParse].
  @override
  String toString() => '$major.$minor';
}
