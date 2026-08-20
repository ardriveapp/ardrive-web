import 'dart:math';
import 'dart:typed_data';

import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:cryptography/cryptography.dart' show SecretKey;

/// The drive state artifact as a *source* for a sync: discovery, fetch,
/// import, and the one log line that says what happened.
///
/// `docs/DRIVE_STATE_ARTIFACT.md` §5 makes the artifact the first of three
/// sources a client reads a drive from:
///
/// ```
/// 1. state artifact   [0 -> Block-End]        one decryption, bulk insert
/// 2. snapshots        (Block-End -> newest]   existing path
/// 3. GraphQL          (newest -> current]     existing path
/// ```
///
/// The three lanes below this one each solved a piece of that and deliberately
/// stopped short of composing them: discovery finds without trusting, the
/// envelope opens without deciding, and the importer merges and *returns* its
/// outcome rather than logging it, because none of them can know a sync
/// reached its end. This is the layer that knows. It is therefore the layer
/// that reports (§7), and the only one that does.
///
/// Two properties are load-bearing, and both are about what this must *not*
/// do:
///
///  * **Every failure is a fallback.** Nothing here throws, and no outcome is
///    an error. A drive with no artifact, an unreachable gateway, a payload
///    that will not open - all of them leave [DriveStateSyncResult.covered]
///    empty, and the sync that called this walks the whole range itself,
///    exactly as it does today.
///  * **It changes nothing on its own.** The only thing it hands back is the
///    range an import already wrote to the database. A caller that ignores the
///    result is left with a slower sync, never a wrong one.
class DriveStateSyncSource {
  DriveStateSyncSource({
    required ArweaveService arweave,
    required DriveStateDiscovery discovery,
    required DriveStateImporter importer,
    DriveStateOutcomeReporter reporter = const DriveStateOutcomeReporter(),
    int maxCandidateAttempts = defaultMaxCandidateAttempts,
  })  : _arweave = arweave,
        _discovery = discovery,
        _importer = importer,
        _reporter = reporter,
        _maxCandidateAttempts = max(1, maxCandidateAttempts);

  /// How many of a drive's artifacts a single sync will pay to download before
  /// giving up and walking the range itself.
  ///
  /// Three, and the number is a budget rather than a policy about artifacts.
  /// Each attempt costs a download sized like a snapshot, so the cost of
  /// looking is the thing to bound; the benefit falls away much faster than
  /// the cost does.
  ///
  ///  * **One is not enough**, which is the whole of this bound's reason to
  ///    exist. An L1 artifact is indexed by GraphQL before its data is
  ///    retrievable, so every publication opens a window in which the newest
  ///    candidate 404s and the previous one - already found, already ordered -
  ///    is fine. One retry closes that window.
  ///  * **A second retry** covers the case that window overlaps something
  ///    else: a publication that failed to seed at all, immediately followed
  ///    by another. Two consecutive unusable artifacts is a real, if unlikely,
  ///    state.
  ///  * **Beyond that the failures stop being independent.** Three unusable
  ///    artifacts in a row is a producer that is broken or hostile, not a
  ///    gateway that is slow, and the fourth download is not more likely to
  ///    help than the third was. The ordinary sync below is the answer at that
  ///    point, and it always works.
  ///
  /// The worst case is bounded at three wasted downloads per drive per sync,
  /// against the alternative of a full GraphQL walk of the drive's history -
  /// which is what the feature exists to avoid, and what happens anyway if
  /// every attempt fails.
  static const int defaultMaxCandidateAttempts = 3;

  final ArweaveService _arweave;
  final DriveStateDiscovery _discovery;
  final DriveStateImporter _importer;

  /// The artifact most recently imported into each drive, this session.
  ///
  /// Not a cache of anything - a record of work already done, so it is not
  /// done again. See the check in [_attempt] for why identity is the
  /// transaction id rather than the block range, and why this is per session.
  final Map<String, String> _importedThisSession = {};
  final DriveStateOutcomeReporter _reporter;
  final int _maxCandidateAttempts;

  /// Reads the best usable artifact this drive has, if it has one, and merges
  /// it.
  ///
  /// *Usable*, not merely newest: discovery returns an ordered list and this
  /// walks it, up to [defaultMaxCandidateAttempts], because the newest
  /// candidate failing is a routine state rather than an end to the matter.
  /// Whatever the walk cost, the drive gets exactly one verdict (§7) - the one
  /// belonging to the candidate that decided the sync.
  ///
  /// [lastBlockHeight] is the height the sync would otherwise start from -
  /// already stepped back by the look-back window. It is used to skip
  /// artifacts that cannot help and to decide whether the artifact's coverage
  /// abuts what is already synced; it is never advanced here. Writing the
  /// watermark is the importer's job, and the range this returns is what tells
  /// the caller how much of its own work the import did.
  ///
  /// Never throws.
  Future<DriveStateSyncResult> read({
    required String driveId,
    required String ownerAddress,
    required SecretKey driveKey,
    required int lastBlockHeight,
  }) async {
    DriveStateSyncResult result;

    try {
      result = await _read(
        driveId: driveId,
        ownerAddress: ownerAddress,
        driveKey: driveKey,
        lastBlockHeight: lastBlockHeight,
      );
    } catch (e) {
      // The outer net. Every layer below reports rather than throws, so
      // reaching here means something unforeseen - and an artifact that has
      // found a new way to be broken still may not fail a drive. Reported as
      // an integrity failure because that is what §7's vocabulary has for
      // "there was an artifact and it was not usable"; the detail carries what
      // actually happened.
      result = DriveStateSyncResult._rejected(
        DriveStateOutcome.integrityFailed,
        'the artifact path threw: $e',
      );
    }

    // One report per drive per sync, whatever happened, and the only one:
    // every layer below this hands its verdict back rather than logging it.
    _report(driveId: driveId, result: result);

    return result;
  }

  Future<DriveStateSyncResult> _read({
    required String driveId,
    required String ownerAddress,
    required SecretKey driveKey,
    required int lastBlockHeight,
  }) async {
    // An artifact mined below the height this sync starts from cannot carry a
    // `Block-End` above it - a producer cannot account for blocks that did not
    // exist when it was mined - so it could only ever be `rangeAlreadyCovered`.
    // Filtering in the query means the indexer does not return it at all.
    final discovered = await _discovery.findCandidates(
      driveId: driveId,
      ownerAddress: ownerAddress,
      minBlockHeight: lastBlockHeight > 0 ? lastBlockHeight : null,
    );

    final candidates = discovered.candidates;

    if (candidates.isEmpty) {
      // "The indexer did not answer" and "this drive has no artifact" are
      // different facts, and §7 forbids letting them look the same. There is
      // no outcome for the first - the vocabulary describes what happened to
      // an artifact, and a query that was never answered produced none - so it
      // is left to the warning [DriveStateDiscovery] already logged, and this
      // returns without a verdict rather than claiming one.
      return discovered.discoveryFailed
          ? DriveStateSyncResult.none
          : DriveStateSyncResult._rejected(
              DriveStateOutcome.noneFound,
              'discovery returned no candidate for this drive',
            );
    }

    // The candidates are newest-first, and until this loop existed only the
    // first of them was ever tried. One unusable artifact took the feature off
    // for the drive entirely - including for the window every publication
    // opens, where the newest is indexed but not yet retrievable and the
    // previous one, in this same list, is fine.
    //
    // So: attempt them in order, up to [_maxCandidateAttempts]. Two outcomes
    // end the walk rather than continue it, and everything else is worth one
    // more try:
    //
    //  * a *used* artifact, obviously - there is nothing better below it;
    //  * `rangeAlreadyCovered`, which is an early exit and not a failure. The
    //    list is ordered by `Block-End` descending, so a candidate at or below
    //    the local watermark guarantees every candidate after it is too.
    //    Walking on would download artifacts that are, by construction,
    //    already covered.
    final budget = min(candidates.length, _maxCandidateAttempts);
    late DriveStateSyncResult result;
    var tried = 0;

    while (tried < budget) {
      final candidate = candidates[tried];
      tried++;

      result = await _attempt(
        driveId: driveId,
        candidate: candidate,
        ownerAddress: ownerAddress,
        driveKey: driveKey,
        lastBlockHeight: lastBlockHeight,
      );

      if (result.artifactWasUsed ||
          result.outcome == DriveStateOutcome.rangeAlreadyCovered) {
        break;
      }

      if (tried < budget) {
        // Not an outcome. §7 gives a drive exactly one verdict per sync, and
        // the verdict is what the sync ended up with; an artifact that was
        // turned down while a usable one was still to come is something that
        // happened on the way to it. [DriveStateOutcomeReporter.note] is
        // worded so neither outcome grep can pick these up.
        _reporter.note(
          driveId: driveId,
          message: 'candidate $tried of ${candidates.length} '
              '(tx=${candidate.txId}) was not usable '
              '(${result.outcome?.code}); trying the next one: '
              '${result.detail}',
          level: DriveStateLogLevel.warning,
        );
      }
    }

    // The one verdict says how it was arrived at when that was not obvious:
    // "artifact rejected - outcome=fetch-failed" reads very differently once
    // it is known that three artifacts were tried and every one of them
    // failed, and a `used` line that took two attempts is the window this
    // whole loop exists for, showing up in the log.
    return tried > 1 ? result._afterAttempts(tried, candidates.length) : result;
  }

  /// One candidate, start to finish: the cheap coverage check, the download,
  /// and the import. Never throws - [read]'s outer net is the backstop, not
  /// the mechanism.
  Future<DriveStateSyncResult> _attempt({
    required String driveId,
    required DriveStateArtifactCandidate candidate,
    required String ownerAddress,
    required SecretKey driveKey,
    required int lastBlockHeight,
  }) async {
    // An artifact this session already imported into this drive.
    //
    // Measured on a 41,767 file drive: re-importing the same artifact costs a
    // 9.55 MiB download, ~173,000 statements and about 8.5 seconds - and
    // writes **zero** rows, because everything in it is already there. That
    // is not a one-off. A successful import leaves `Block-End` and the drive's
    // watermark *equal*, and the importer's no-rollback guard refuses only
    // `Block-End < watermark`, so nothing stops the next sync from doing it
    // all again, on the `autoSync` interval, forever.
    //
    // The guard has to stay `<` rather than become `<=`: an artifact whose
    // range the drive already covers can still carry entities a *consumer's*
    // sync skipped, and importing it is how those get repaired. What must not
    // repeat is re-importing **this same artifact**, whose rows this drive
    // demonstrably already holds. So the identity checked here is the
    // transaction id, not the range - a different artifact at the same
    // `Block-End` is still worth reading.
    //
    // Per session, deliberately. Persisting it would mean a schema migration
    // to hold one transaction id per drive, and the cost this avoids is
    // per-sync rather than per-launch: a user pays it once after a restart
    // instead of every few minutes.
    if (_importedThisSession[driveId] == candidate.txId) {
      return DriveStateSyncResult._rejected(
        DriveStateOutcome.rangeAlreadyCovered,
        'this artifact was already imported into this drive during this '
        'session',
        txId: candidate.txId,
      );
    }

    // Cheap enough to be worth doing before a download of tens of megabytes,
    // and only ever an early exit: the authoritative version of this rule is
    // the importer's, against the drive row rather than this sync's
    // look-back-adjusted start, and it still runs for everything that gets
    // past here.
    final blockEnd = candidate.blockEnd;
    if (blockEnd != null && blockEnd < lastBlockHeight) {
      return DriveStateSyncResult._rejected(
        DriveStateOutcome.rangeAlreadyCovered,
        'Block-End $blockEnd is below the $lastBlockHeight this sync starts '
        'from',
        txId: candidate.txId,
      );
    }

    final Uint8List body;
    try {
      // The gateway seam every other sync read goes through: configured
      // gateway, one retry, then give up. `largeBody` because an artifact is
      // sized like a snapshot, not like entity metadata.
      body = await _arweave.getEntityDataFromNetwork(
        txId: candidate.txId,
        largeBody: true,
      );
    } catch (e) {
      // A verdict, unlike a discovery query that did not answer. The
      // difference is that this artifact is *identified* - there is a
      // transaction id - so the fact recorded is about the artifact rather
      // than about the lookup, and a count of "drives that had an artifact
      // and used one" needs it in the denominator. See §7.
      return DriveStateSyncResult._rejected(
        DriveStateOutcome.fetchFailed,
        'the body could not be fetched: $e',
        txId: candidate.txId,
      );
    }

    final imported = await _importer.import(
      candidate: candidate,
      body: body,
      driveKey: driveKey,
      expectedOwnerAddress: ownerAddress,
    );

    // Recorded only on success. A rejected artifact is not "work already
    // done" - a fetch that failed or a payload that did not verify is worth
    // retrying next sync, when the gateway may answer differently.
    if (imported.outcome.artifactWasUsed) {
      _importedThisSession[driveId] = candidate.txId;
    }

    return DriveStateSyncResult._fromImport(imported, candidate);
  }

  void _report({
    required String driveId,
    required DriveStateSyncResult result,
  }) {
    final outcome = result.outcome;
    if (outcome == null) return;

    _reporter.report(
      driveId: driveId,
      outcome: outcome,
      txId: result.txId,
      detail: result.detail,
    );
  }
}

/// What the artifact left for the rest of the sync to do.
///
/// [covered] is the whole point: the blocks whose entities are already in the
/// database when this returns. It is an obscuring range in exactly the sense
/// `SnapshotItem.instantiateAll` uses - the accumulator there seeds itself
/// with the blocks a sync need not look at again, and this is one more of
/// them - so a caller composes it with `HeightRange.difference` and nothing
/// else.
///
/// It is empty for every outcome but [DriveStateOutcome.used], including every
/// failure, which is what makes ignoring an artifact indistinguishable from
/// never having looked for one.
class DriveStateSyncResult {
  DriveStateSyncResult._({
    required this.covered,
    this.outcome,
    this.detail,
    this.txId,
  });

  DriveStateSyncResult._rejected(
    DriveStateOutcome outcome,
    String detail, {
    String? txId,
  }) : this._(
          covered: _emptyRange(),
          outcome: outcome,
          detail: detail,
          txId: txId,
        );

  factory DriveStateSyncResult._fromImport(
    DriveStateImportResult imported,
    DriveStateArtifactCandidate candidate,
  ) {
    if (!imported.isImported) {
      return DriveStateSyncResult._rejected(
        imported.outcome,
        imported.detail,
        txId: candidate.txId,
      );
    }

    // The coverage comes from the tags the import verified the payload
    // against, never from the payload: `Block-Start` is read rather than
    // assumed to be 0 (§3.4 is a v1 policy, not a property of the format), and
    // the importer applies the same reasoning to the watermark it writes.
    final blockStart = candidate.blockStart ?? 0;
    final watermark = imported.stats!.watermark;

    return DriveStateSyncResult._(
      // An artifact whose coverage begins above what this client has synced
      // leaves a gap, and the importer says so by declining to move the
      // watermark: its rows land - they can only add - but the range they came
      // from is not this sync's to skip. Obscuring it anyway would jump the
      // GraphQL pass over the gap and lose whatever is in it permanently,
      // which is the silent drop this whole line of work exists to avoid.
      covered: blockStart <= watermark
          ? HeightRange(rangeSegments: [
              Range(start: blockStart, end: watermark),
            ])
          : _emptyRange(),
      outcome: imported.outcome,
      detail: imported.detail,
      txId: candidate.txId,
    );
  }

  /// The same verdict, with the walk that produced it named in its detail.
  ///
  /// Only the detail moves. The outcome, the range and the transaction id all
  /// belong to the candidate that actually decided the sync, and a count that
  /// changed any of them would make "an artifact was used" ambiguous about
  /// *which* artifact - which is the confusion §7's vocabulary exists to
  /// prevent.
  DriveStateSyncResult _afterAttempts(int tried, int discovered) {
    final walked = 'after $tried of $discovered candidate(s)';
    final existing = detail;

    return DriveStateSyncResult._(
      covered: covered,
      outcome: outcome,
      detail:
          existing == null || existing.isEmpty ? walked : '$existing - $walked',
      txId: txId,
    );
  }

  /// Nothing was learned and nothing was imported: no range, and nothing to
  /// report. Used where a failure happened *before* any verdict on an artifact
  /// was possible - a discovery query that went unanswered, a body that could
  /// not be fetched - both of which log their own warning.
  static DriveStateSyncResult get none =>
      DriveStateSyncResult._(covered: _emptyRange());

  /// Blocks the artifact's rows already account for. Empty unless an import
  /// landed.
  final HeightRange covered;

  /// Null only when there is no verdict to report - see [none].
  final DriveStateOutcome? outcome;

  /// The `detail` clause for the report: the reason for a rejection, the
  /// measurements for an import.
  final String? detail;

  final String? txId;

  bool get artifactWasUsed => outcome?.artifactWasUsed ?? false;

  /// The highest block [covered] accounts for, or 0 when nothing is covered.
  ///
  /// This is the form a caller wants: the obscured prefix is contiguous from
  /// the drive's beginning, so one height describes it, and it is exactly the
  /// `lastBlockHeight` seed `SnapshotItem.instantiateAll` already takes.
  int get coveredThroughBlock => covered.rangeSegments
      .fold(0, (highest, segment) => max(highest, segment.end));
}

/// A [HeightRange] over no blocks at all.
///
/// Built fresh each time rather than shared: [HeightRange] keeps its segments
/// in a mutable list, and one shared empty instance is one `add` away from
/// obscuring a range nobody asked it to.
HeightRange _emptyRange() => HeightRange(rangeSegments: []);
