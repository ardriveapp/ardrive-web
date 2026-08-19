import 'package:ardrive/utils/logger.dart';

/// Why a sync did, or did not, use a drive state artifact — and the logging
/// that makes the difference visible.
///
/// `docs/DRIVE_STATE_ARTIFACT.md` §7 exists because the failure this whole
/// line of work came from was **silent**: sync fell back to a slower path and
/// nothing said why, which cost days of diagnosis. The governing rule it sets
/// is the one this file enforces:
///
/// > **"no artifact was used" and "an artifact was rejected because X" must
/// > never look the same.**
///
/// So the vocabulary is enumerated, not free text, and every value prints a
/// distinct, greppable line. The prefix is `[drive-state]`, deliberately the
/// same shape as the `[snapshot]` instrumentation already in
/// `arweave_service.dart` and `sync_repository.dart` — §7 asks this to extend
/// that vocabulary rather than invent a second one.

/// What happened to the artifact, at the coarsest granularity a reader cares
/// about. This is what keeps the three cases textually separate in a log:
/// something was used, nothing existed to use, or something existed and was
/// turned down.
enum DriveStateOutcomeKind {
  /// An artifact was read and its rows imported.
  used,

  /// There was no artifact to consider. Not a fault, and not a rejection.
  nothingFound,

  /// An artifact was found and deliberately not used. Always carries a reason.
  rejected,
}

/// The enumerated outcomes from §7.
///
/// Every value is one of: the artifact was used, or one of the reasons it was
/// not. Nothing here fails a drive — decision "every failure is a fallback"
/// (`docs/drive-state/DECISIONS.md`) means each rejection is followed by a
/// normal sync, so these are diagnostics, never errors.
enum DriveStateOutcome {
  /// The artifact verified, decrypted and imported.
  used(
    code: 'used',
    kind: DriveStateOutcomeKind.used,
    description: 'the artifact verified and its rows were imported',
  ),

  /// Discovery found no artifact for this drive. The common case today, and
  /// the one that must never be confused with a rejection.
  noneFound(
    code: 'none-found',
    kind: DriveStateOutcomeKind.nothingFound,
    description: 'no drive-state artifact exists for this drive',
  ),

  /// `State-Version` names a format this build cannot read (§6). An older
  /// reader meeting a newer artifact is expected, not broken.
  unknownVersion(
    code: 'unknown-version',
    kind: DriveStateOutcomeKind.rejected,
    description: 'State-Version is newer than this build can read',
  ),

  /// The payload signature did not verify against the drive owner (§2.2).
  /// Authorship travels with the payload, not the transaction header, so this
  /// is the check that holds for a bundled data item as well as an L1
  /// transaction (§4.4).
  signatureFailed(
    code: 'signature-failed',
    kind: DriveStateOutcomeKind.rejected,
    description: 'the payload signature did not verify for the drive owner',
  ),

  /// AES256-GCM decryption failed — wrong key, or the ciphertext did not
  /// authenticate.
  decryptFailed(
    code: 'decrypt-failed',
    kind: DriveStateOutcomeKind.rejected,
    description: 'the payload could not be decrypted with the drive key',
  ),

  /// The plaintext decrypted but did not hold what the tags promised: a
  /// missing section, a malformed row, or a `Drive-Id` that disagrees with the
  /// drive being synced.
  integrityFailed(
    code: 'integrity-failed',
    kind: DriveStateOutcomeKind.rejected,
    description: 'the payload did not match the shape its tags declared',
  ),

  /// `Entity-Count` disagreed with the number of entities imported (§3.2).
  /// GCM proves the ciphertext arrived intact; this proves the body meant what
  /// the tags promised.
  countMismatch(
    code: 'count-mismatch',
    kind: DriveStateOutcomeKind.rejected,
    description: 'Entity-Count disagreed with the entities in the payload',
  ),

  /// The `Block-Start` / `Block-End` tags disagree with the coverage the
  /// payload itself claims (§3.2). Kept apart from [integrityFailed] because
  /// it is the one rejection that says *somebody re-published somebody else's
  /// artifact under a coverage of their choosing*: the bytes verify, the drive
  /// and the entity count match, and only the range is a lie. A log that
  /// blurred it into "the payload did not match its tags" would hide the
  /// difference between a damaged artifact and an attempt to jump a drive's
  /// watermark past unsynced blocks.
  coverageMismatch(
    code: 'coverage-mismatch',
    kind: DriveStateOutcomeKind.rejected,
    description: 'the coverage tags disagreed with the signed payload',
  ),

  /// Discovery named an artifact and its body could not be read from the
  /// gateway.
  ///
  /// Inside the vocabulary, where "the indexer never answered" deliberately is
  /// not (§7). The line between them is that by this point a *specific*
  /// artifact has been identified, by transaction id, so the fact recorded is
  /// about that artifact rather than about the lookup. A consumer asking how
  /// many drives that had an artifact actually used one gets a wrong
  /// denominator if this is only a log line.
  fetchFailed(
    code: 'fetch-failed',
    kind: DriveStateOutcomeKind.rejected,
    description: 'the artifact was found but its body could not be fetched',
  ),

  /// The artifact covers a range the local database already holds, so reading
  /// it would cost a download and change nothing. Found and declined, which is
  /// why it is a rejection and not `noneFound` — but it is not a fault.
  rangeAlreadyCovered(
    code: 'range-already-covered',
    kind: DriveStateOutcomeKind.rejected,
    description: 'the artifact range is already covered locally',
  );

  const DriveStateOutcome({
    required this.code,
    required this.kind,
    required this.description,
  });

  /// The stable token that appears in the log as `outcome=<code>`. Grep for
  /// this; the prose around it may be reworded, this may not.
  final String code;

  final DriveStateOutcomeKind kind;

  /// Human-readable clause explaining the code. Never the thing to grep for.
  final String description;

  /// Whether an artifact was actually used. The single question §7 asks first.
  bool get artifactWasUsed => kind == DriveStateOutcomeKind.used;

  /// Whether something went wrong with an artifact that existed, as opposed to
  /// there being nothing to use ([noneFound]) or nothing worth using
  /// ([rangeAlreadyCovered]). Drives the log level, so that the ordinary path
  /// does not shout.
  bool get isFault =>
      kind == DriveStateOutcomeKind.rejected && this != rangeAlreadyCovered;
}

/// Severity of a reported line. Deliberately only two: nothing in this
/// vocabulary is an error, because every one of these outcomes is followed by
/// a normal sync.
enum DriveStateLogLevel { info, warning }

/// Where a [DriveStateOutcomeReporter] writes. Injectable so tests can read
/// exactly what would be logged without going through the global logger.
typedef DriveStateLogSink = void Function(
  DriveStateLogLevel level,
  String message,
);

void _defaultSink(DriveStateLogLevel level, String message) {
  switch (level) {
    case DriveStateLogLevel.info:
      logger.i(message);
      break;
    case DriveStateLogLevel.warning:
      logger.w(message);
      break;
  }
}

/// Logs [DriveStateOutcome]s under the `[drive-state]` prefix.
///
/// Small on purpose: this lane owns the vocabulary, not the measurements. The
/// per-source entity counts and the parse-versus-import timings §7 also asks
/// for ride along in [detail], so the import lane can add them without a
/// second vocabulary.
class DriveStateOutcomeReporter {
  /// Grep for this to get every line this feature emits.
  static const String logPrefix = '[drive-state]';

  const DriveStateOutcomeReporter({DriveStateLogSink? sink})
      : _sink = sink ?? _defaultSink;

  final DriveStateLogSink _sink;

  /// Builds the line for an outcome without logging it.
  ///
  /// The three kinds open with three different phrases — `artifact used`,
  /// `no artifact was used`, `artifact rejected` — and none of them is a
  /// substring of another, so `grep 'artifact used'` can never return a drive
  /// that had no artifact, and `grep 'artifact rejected'` can never return one
  /// that had none to reject. `outcome=<code>` is the exact token for a single
  /// outcome.
  static String formatLine({
    required String driveId,
    required DriveStateOutcome outcome,
    String? txId,
    String? detail,
  }) {
    final buffer = StringBuffer('$logPrefix $driveId: ');

    switch (outcome.kind) {
      case DriveStateOutcomeKind.used:
        buffer.write('artifact used');
        break;
      case DriveStateOutcomeKind.nothingFound:
        buffer.write('no artifact was used');
        break;
      case DriveStateOutcomeKind.rejected:
        buffer.write('artifact rejected');
        break;
    }

    buffer.write(' - outcome=${outcome.code} - ${outcome.description}');

    if (txId != null) {
      buffer.write(' - tx=$txId');
    }

    if (detail != null && detail.isNotEmpty) {
      buffer.write(' - $detail');
    }

    return buffer.toString();
  }

  /// The level a given outcome is logged at. A rejection that is nobody's
  /// fault ([DriveStateOutcome.rangeAlreadyCovered]) and the ordinary
  /// "no artifact exists" case stay at info; anything that says an artifact
  /// was there and unusable is a warning.
  static DriveStateLogLevel levelFor(DriveStateOutcome outcome) =>
      outcome.isFault ? DriveStateLogLevel.warning : DriveStateLogLevel.info;

  /// Records what a sync did with a drive's artifact. Call exactly once per
  /// drive per sync, whatever happened.
  void report({
    required String driveId,
    required DriveStateOutcome outcome,
    String? txId,
    String? detail,
  }) {
    _sink(
      levelFor(outcome),
      formatLine(
        driveId: driveId,
        outcome: outcome,
        txId: txId,
        detail: detail,
      ),
    );
  }

  /// Records something that happened on the way to an outcome — a failed
  /// discovery query, a candidate discarded before it was ever fetched.
  ///
  /// Kept separate from [report] because these are not outcomes: a drive still
  /// gets exactly one [report] afterwards. The wording avoids all three
  /// outcome sentences so that neither grep picks these up by accident.
  void note({
    required String driveId,
    required String message,
    DriveStateLogLevel level = DriveStateLogLevel.info,
  }) {
    _sink(level, '$logPrefix $driveId: $message');
  }
}
