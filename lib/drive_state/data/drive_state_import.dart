
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive/models/license.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/drive_state_sqlite/artifact_sink.dart';
import 'package:ardrive/drive_state_sqlite/artifact_to_export.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_import.dart';
import 'package:ardrive/sync/utils/network_transaction_utils.dart';
import 'package:ardrive_utils/ardrive_utils.dart'
    show DrivePrivacyTag, EntityTag;
import 'package:arweave/utils.dart' as utils;
import 'package:drift/drift.dart';

/// Opening a drive state artifact and merging it into the local database.
///
/// The exact inverse of `drive_state_export.dart`, plus the two things an
/// exporter never has to think about: whether the bytes can be trusted, and
/// what to do when the database already knows something the artifact does not.
///
/// Three rules from `docs/DRIVE_STATE_ARTIFACT.md` shape all of it.
///
///  * **Validate before merging** (§2.5). Signature first, then drive
///    identity, then `Entity-Count`, then coverage. Every check runs before
///    the first write, and the writes are a single transaction, because a half
///    imported drive is worse than one that never imported at all.
///  * **Import is a merge, not a replace** (§5). The database holds every
///    drive and every profile; an artifact holds one drive. Nothing outside
///    that drive is read or written, no row is ever deleted, and a local row
///    newer than the artifact's copy of it wins.
///  * **Failure is silence, not error** (§2.5). Nothing here throws. Every
///    path out is a [DriveStateOutcome] the caller reports before syncing the
///    ordinary way, because no drive may fail because an artifact was bad.

/// What an import did, for the log line §7 asks for.
///
/// §7 wants a sync to be able to say how many entities came from an artifact,
/// and to weigh time spent parsing against time spent writing. These are those
/// numbers, gathered here because this is the only layer that sees both
/// halves. [DriveStateOutcomeReporter] takes them as its `detail`, which is
/// how the measurements reach the log without a second vocabulary.
class DriveStateImportStats {
  /// Rows written to `folder_entries` and `file_entries`.
  final int foldersWritten;
  final int filesWritten;

  /// Stand-in `folder_entries` rows the merge invented so that every
  /// `parentFolderId` it wrote resolves — see [DriveStateImporter]'s row graph
  /// section.
  ///
  /// Reported because it is the number that says *this drive arrived with
  /// holes in it*. Non-zero is normal, not a fault: a producer's ghost folder
  /// cannot travel, so its consumer rebuilds one. A number that climbs across
  /// a fleet is the signal that producers are publishing while unresolved
  /// metadata is still outstanding, and §7 exists so that signal is in the log
  /// rather than inferred from a screenshot.
  ///
  /// Defaulted rather than required: it is a measurement added after the
  /// vocabulary settled, and the callers that build this by hand are naming
  /// what they assert on.
  final int foldersMaterialised;

  /// Rows added to `drive_revisions`, `folder_revisions` and `file_revisions`,
  /// and to `licenses`.
  ///
  /// Counted separately from the entities because they are not entities — see
  /// [DriveStateExport.entityCount]. They are here because they are most of
  /// the payload and all of the reason the file list renders at all, so an
  /// import that landed entities and no revisions has to be visible in the
  /// log rather than inferred from an empty screen.
  final int revisionsWritten;
  final int licensesWritten;

  /// `network_transactions` rows regenerated from those revisions.
  final int transactionsWritten;

  /// Rows the artifact carried that were *not* written, because the local copy
  /// was newer. Not an error — it is the number that explains an import
  /// landing fewer rows than its `Entity-Count`.
  final int rowsKeptLocallyNewer;

  /// The `lastBlockHeight` the drive was left on. Normally the end of the
  /// payload's signed coverage claim; see [DriveStateImporter] for the one
  /// case where it is not, and for why it never comes from a tag alone.
  final int watermark;

  /// Decrypt, verify, decompress, parse.
  final Duration parseDuration;

  /// The database transaction.
  final Duration mergeDuration;

  const DriveStateImportStats({
    required this.foldersWritten,
    this.foldersMaterialised = 0,
    required this.filesWritten,
    required this.revisionsWritten,
    required this.licensesWritten,
    required this.transactionsWritten,
    required this.rowsKeptLocallyNewer,
    required this.watermark,
    required this.parseDuration,
    required this.mergeDuration,
  });

  int get entitiesImported => foldersWritten + filesWritten;

  /// The `detail` clause for [DriveStateOutcomeReporter.report].
  @override
  String toString() => 'imported=$entitiesImported '
      '(folders=$foldersWritten files=$filesWritten '
      'kept-local=$rowsKeptLocallyNewer '
      'materialised-folders=$foldersMaterialised) '
      'revisions=$revisionsWritten licenses=$licensesWritten '
      'transactions=$transactionsWritten '
      'watermark=$watermark '
      'parse=${parseDuration.inMilliseconds}ms '
      'merge=${mergeDuration.inMilliseconds}ms';
}

/// The outcome of an import, and either what it did or why it did nothing.
///
/// Returned rather than logged. §7 asks for exactly one report per drive per
/// sync, and the layer that composes discovery, fetch and import is the only
/// one that knows it has reached the end — so this carries everything
/// [DriveStateOutcomeReporter.report] needs and lets that layer make the call.
class DriveStateImportResult {
  final DriveStateOutcome outcome;

  /// The `detail` clause for the report: the reason when the artifact was
  /// rejected, the measurements when it was used. Never for the user.
  final String detail;

  /// `null` unless [isImported].
  final DriveStateImportStats? stats;

  const DriveStateImportResult._(this.outcome, this.detail, this.stats);

  DriveStateImportResult.imported(DriveStateImportStats stats)
      : this._(DriveStateOutcome.used, stats.toString(), stats);

  const DriveStateImportResult.rejected(
    DriveStateOutcome outcome,
    String detail,
  ) : this._(outcome, detail, null);

  bool get isImported => outcome == DriveStateOutcome.used;

  @override
  String toString() => '${outcome.code}: $detail';
}

extension DriveStateEnvelopeFailureOutcome on DriveStateEnvelopeFailure {
  /// The coarser outcome this codec failure reports as.
  ///
  /// The codec distinguishes thirteen ways an artifact can be unreadable
  /// because it is the layer that can tell them apart. A reader of a sync log
  /// wants the answer to *why did this drive not use its artifact*, and
  /// thirteen shades of "it did not open" would bury it — so §7's vocabulary is coarser
  /// on purpose, and the envelope lane left this mapping to whoever composes
  /// it. The precision is not lost: it travels in
  /// [DriveStateImportResult.detail], which carries the codec's own reason
  /// string verbatim.
  ///
  /// A switch expression on purpose: a failure added to
  /// [DriveStateEnvelopeFailure] with no case here is a compile error, not a
  /// value that quietly maps to whatever a `default` branch happened to say.
  DriveStateOutcome get outcome => switch (this) {
        // Seal-side refusals. `open` cannot return these — they are refusals
        // to *produce* an artifact — but the switch stays total so the codec
        // lane can add a reason without knowing this file exists, and this
        // file stops the build until someone decides what it means here.
        DriveStateEnvelopeFailure.plaintextTooLarge =>
          DriveStateOutcome.integrityFailed,
        DriveStateEnvelopeFailure.signingFailed =>
          DriveStateOutcome.integrityFailed,
        DriveStateEnvelopeFailure.compressionFailed =>
          DriveStateOutcome.integrityFailed,

        // A cipher this build does not know is the same situation as an
        // unknown `State-Version`: forward compatibility seen from the old
        // side (§6), not a defect.
        DriveStateEnvelopeFailure.unsupportedCipher =>
          DriveStateOutcome.unknownVersion,

        // The cipher/privacy cross-check, both directions. Not
        // `integrityFailed`: the payload may be perfectly well formed, and
        // what is wrong is that its cipher-presence contradicts the privacy
        // of the drive it claims to be for. Its own code for the same reason
        // `coverageMismatch` has one — a log that blurred it into "the
        // payload did not match its tags" would hide a private drive being
        // offered an artifact in the clear.
        DriveStateEnvelopeFailure.plaintextForPrivateDrive =>
          DriveStateOutcome.privacyMismatch,
        DriveStateEnvelopeFailure.ciphertextForPublicDrive =>
          DriveStateOutcome.privacyMismatch,

        // A signature scheme this build cannot verify is *not* that. Nothing
        // about the artifact's authorship has been established - the check
        // simply could not be run - and reporting it as "your client is old"
        // would put an unverifiable artifact in the same log line as a
        // legitimately newer one. It is a rejection for want of a signature,
        // which is what `signatureFailed` says.
        DriveStateEnvelopeFailure.unsupportedSignatureType =>
          DriveStateOutcome.signatureFailed,
        DriveStateEnvelopeFailure.decryptionFailed =>
          DriveStateOutcome.decryptFailed,

        // The bytes came out, and were not what they claimed to be.
        DriveStateEnvelopeFailure.decompressionFailed =>
          DriveStateOutcome.integrityFailed,
        DriveStateEnvelopeFailure.decompressedTooLarge =>
          DriveStateOutcome.integrityFailed,
        DriveStateEnvelopeFailure.malformedFrame =>
          DriveStateOutcome.integrityFailed,

        // Signed by the wrong wallet, or not by the wallet it names. Both mean
        // the same thing to a caller: do not trust these bytes.
        DriveStateEnvelopeFailure.ownerMismatch =>
          DriveStateOutcome.signatureFailed,
        DriveStateEnvelopeFailure.signatureInvalid =>
          DriveStateOutcome.signatureFailed,
      };
}

/// Merges one drive state artifact into the local database.
///
/// ## What "merge" means, precisely
///
/// The artifact is a **cache of one drive, not the truth about the database**.
/// So:
///
///  * rows are matched by primary key and written only when the artifact's
///    copy is at least as recent as the local one, by `lastUpdated`;
///  * a local row the artifact has never heard of is left alone. It is far
///    likelier to be something uploaded since the artifact was published than
///    something removed, and an artifact that deleted rows would turn one
///    stale publication into data loss;
///  * a local row that is *newer* is only newer if something vouches for it.
///    The two rows this client fabricates — a ghost folder
///    (`SyncRepository.createGhosts`) and a root folder placeholder
///    (`DriveDao._rootFolderPlaceholder`) — are stamped with *now*, while the
///    artifact's genuine row carries its chain commit time, so a timestamp
///    comparison alone hands every contest to the stand-in and the artifact
///    can never heal one. See [_folderStandInLoses] for the predicate that
///    fixes it and for why it is scoped to `folder_entries`;
///  * the revision tables obey the same rule, arrived at differently. Their
///    primary keys *contain* their version — a revision is keyed by
///    `(entityId, driveId, dateCreated)` — so a newer copy of a row is not a
///    conflicting write, it is a different key. There is therefore nothing for
///    a `lastUpdated` comparison to decide: the artifact can only add, and a
///    row the client already holds is left exactly as it is. That is what
///    [InsertMode.insertOrIgnore] says, and it is strictly the safer half of
///    the same policy;
///  * `licenses` lands the same way for a different reason, and it is worth
///    stating because the obvious one is wrong: its primary key is
///    `(fileId, driveId, dataTxId, licenseTxId)` and holds no version at all.
///    Two rows sharing that key are not two versions of a licence — they are
///    the same licence transaction attached to the same file data
///    transaction. Every remaining column describes that transaction, is read
///    from the chain, and is never edited afterwards: `DriveDao.insertLicense`
///    only ever inserts, and re-licensing a file mints a new `licenseTxId`,
///    which is a new key and so a new row. An overwrite would therefore write
///    back the values already there; ignoring is the cheaper and the safer of
///    two statements with the same effect;
///  * `network_transactions` is not in the payload at all. It is rebuilt from
///    the revisions above through the same `lib/sync/utils/` helpers sync
///    derives it with, and inserted the same way — a status this client
///    established for itself is never overwritten by a derived one;
///  * the drive's key material and its sync cursor are never touched. They are
///    not in the payload — [ExportedDrive] structurally has nowhere to put
///    them — and the update names its columns, so they cannot be nulled out by
///    accident either;
///  * no statement here can see another drive's rows.
///
/// ## The row graph
///
/// A drive is a tree, and the merge has to leave one behind. Two ways it would
/// not, both reachable from an *honest* producer, and both permanent because
/// the import advances the watermark past the range whose metadata would have
/// repaired them:
///
///  * **A parent that is in no section.** The export publishes only rows a
///    revision vouches for, and a ghost folder has no revision by definition —
///    that is what makes it a ghost. The files inside it do have revisions, so
///    they travel and their parent does not. Nothing in this app lists a file
///    except by its parent, so such a file is in the database and in no
///    folder. Every `parentFolderId` this merge writes is therefore resolved
///    before the first statement runs, and one that resolves neither in the
///    payload nor in this database is *materialised* — see
///    [_ghostFolderStandIn]. Materialised here rather than carried, because a
///    fabricated row must never travel: it is stamped `now` and would outrank
///    every real row in every client that imported it
///    (`_folderEntryCameFromChain`).
///  * **A `rootFolderId` that is in no section.** [_driveCompanion] adopts the
///    payload's `rootFolderId`, and `DriveDao` records what a missing root
///    folder row costs: `watchFolderContents` drops it with a `.where` and its
///    combined stream never emits, stranding the explorer on a spinner that
///    nothing retries, while `getFolderTree` throws outright. A payload naming
///    a root this client cannot resolve either is **refused**, not repaired —
///    see [_merge]. Inventing that row would leave the drive opening onto an
///    empty folder while its real contents hang off the root it used to have,
///    for ever: coverage equals the watermark the import just wrote, and the
///    rollback guard only declines *lower* coverage, so the same payload
///    re-applies on every sync and undoes what `updateUserDrives` repaired.
///    Refusing costs one ordinary sync and leaves the drive correct.
///
/// ## The watermark
///
/// `lastBlockHeight` comes from the payload's **signed** coverage claim
/// ([DriveStateCoverage]), and the `Block-Start` / `Block-End` tags have to
/// agree with it or the artifact is refused outright.
///
/// The tags alone cannot carry this. A transaction tag is chosen by whoever
/// submits the transaction, so a third party can take an owner's artifact
/// bytes unchanged — they verify, they decrypt, their `Drive-Id` and
/// `Entity-Count` match, because they are the owner's bytes — re-publish them
/// under `Block-End: 9999999`, and have every check but this one pass. The
/// watermark would jump to a height nothing was ever synced to and that range
/// would never be queried again: the silent drop in
/// `SYNC_SKIPPED_ENTITY_PERSISTENCE.md`, which is the failure this whole line
/// of work started from. The tags stay because discovery has to order
/// candidates without downloading them; they are checked, not believed.
///
/// `Block-Start` matters for the same reason and is checked the same way.
/// Every artifact this client publishes covers `[0, Block-End]` (§3.4), but
/// that is a v1 policy and not a property of the format. An artifact whose
/// coverage starts *above* what this client has synced leaves a gap, and
/// adopting its `Block-End` would jump the watermark over that gap. Its rows
/// are still merged — they can only add — but the watermark stays where it was
/// and sync walks the range itself.
class DriveStateImporter {
  final DriveDao _driveDao;
  final DriveStateEnvelopeCodec _codec;

  DriveStateImporter(
    this._driveDao, {
    DriveStateEnvelopeCodec? codec,
  }) : _codec = codec ?? DriveStateEnvelopeCodec();

  /// Opens [body] — the artifact transaction's data — under [protection],
  /// checks it was signed by [expectedOwnerAddress], and merges it into the
  /// drive named by [candidate]'s `Drive-Id` tag.
  ///
  /// [candidate] is the discovery lane's product: a transaction id and the
  /// tags an untrusted indexer reported for it. Nothing it says is believed
  /// here either — the tags are what the payload is checked *against*, which
  /// is the only reason they are worth having.
  ///
  /// [protection] is the opposite kind of value: it is resolved from this
  /// client's own drive row, so it is the trustworthy half of the
  /// cipher/privacy cross-check the tag checks below run.
  ///
  /// Never throws.
  Future<DriveStateImportResult> import({
    required DriveStateArtifactCandidate candidate,
    required Uint8List body,
    required DriveStateProtection protection,
    required String expectedOwnerAddress,
  }) async {
    try {
      return await _import(
        candidate: candidate,
        body: body,
        protection: protection,
        expectedOwnerAddress: expectedOwnerAddress,
      );
    } catch (e) {
      // The outer net. Everything below reports rather than throws, so
      // reaching here means something unforeseen — a database that went away
      // mid-merge, a decoder that found a new way to be unhappy. It is still
      // only ever a fallback: the drive syncs normally.
      return DriveStateImportResult.rejected(
        DriveStateOutcome.integrityFailed,
        'the import of ${candidate.txId} threw: $e',
      );
    }
  }

  Future<DriveStateImportResult> _import({
    required DriveStateArtifactCandidate candidate,
    required Uint8List body,
    required DriveStateProtection protection,
    required String expectedOwnerAddress,
  }) async {
    final stopwatch = Stopwatch()..start();

    // 1. The tags. Every one of these getters is lenient by design — the
    //    indexer that reported them is untrusted, and a malformed tag must
    //    produce a reason, not an exception.
    final driveId = candidate.driveId;
    final blockEnd = candidate.blockEnd;
    // Absent reads as 0: §3.4's v1 artifacts all start there, and a tag that
    // disagrees with the signed claim is caught below either way.
    final blockStart = candidate.blockStart ?? 0;
    final declaredCount = candidate.entityCount;
    final cipher = candidate.cipher;
    final cipherIv = candidate.cipherIv;

    if (driveId == null || blockEnd == null || declaredCount == null) {
      return DriveStateImportResult.rejected(
        DriveStateOutcome.integrityFailed,
        'a required tag is missing or unreadable on ${candidate.txId}: '
        'Drive-Id=$driveId Block-End=${candidate.tag(EntityTag.blockEnd)} '
        'Entity-Count=${candidate.tag(EntityTag.entityCount)}',
      );
    }

    // 1b. The cipher tags, which are required together or not at all.
    //
    //     A `Cipher` with no `Cipher-IV` is ciphertext nothing can address; a
    //     `Cipher-IV` with no `Cipher` reads as an unencrypted artifact to
    //     anything that dispatches on cipher-presence, which is what the check
    //     after this one does. Neither is a shape a producer can emit, and
    //     letting either through would mean deciding privacy from one of two
    //     tags that disagree.
    if ((cipher == null) != (cipherIv == null)) {
      return DriveStateImportResult.rejected(
        DriveStateOutcome.integrityFailed,
        'the cipher tags on ${candidate.txId} are incomplete: '
        'Cipher=${cipher ?? 'absent'} '
        'Cipher-IV=${cipherIv == null ? 'absent' : 'set'}',
      );
    }

    // 1c. The cipher/privacy cross-check, in both directions (§2.6).
    //
    //     The same shape as the `Block-Start`/`Block-End` check at step 8: a
    //     claim from an untrusted source, checked against something
    //     trustworthy. What the tags say about encryption is chosen by
    //     whoever posted the transaction; [protection] came from this
    //     client's own drive row.
    //
    //     Run here, before the body is touched, so a plaintext body offered
    //     to a private drive is never parsed and an encrypted one offered to
    //     a public drive is never handed to a decryptor with no key. The
    //     codec repeats the check as its own guard — it must, because it is
    //     the layer that decides whether to decrypt — and this one exists so
    //     the rejection can be reported against the *tags*, which is where
    //     the contradiction actually is.
    final artifactIsEncrypted = cipher != null;
    if (protection.isEncrypted != artifactIsEncrypted) {
      return DriveStateImportResult.rejected(
        DriveStateOutcome.privacyMismatch,
        protection.isEncrypted
            ? 'drive $driveId is private and ${candidate.txId} carries no '
                'Cipher tag; a private drive is never published in the clear'
            : 'drive $driveId is public and ${candidate.txId} declares '
                'Cipher=$cipher; a public drive has no key to open it with',
      );
    }

    // 2. `State-Version`, `major.minor` (§6). A version this build does not
    //    read is skipped, never guessed at — and the three ways that can
    //    happen are reported as three different things, because they are.
    //
    //    This is the tag, which nobody signs; the payload repeats the claim
    //    inside the signature and step 5 cross-checks the two. Reading it here
    //    is still worth it: it is the only version available before the body
    //    is decrypted, so it settles the common forward-compatibility case
    //    without spending a signature verification on an artifact this build
    //    was never going to read.
    const currentVersion = DriveStateFormatVersion.current;
    final taggedVersion = DriveStateFormatVersion.tryParse(
      candidate.stateVersion,
    );

    if (taggedVersion == null) {
      // Not `unknownVersion`. A version that cannot be parsed is not a version
      // that can be compared, so nothing has been established about whether
      // this build could have read the artifact — the same distinction the
      // envelope's `unsupportedSignatureType` draws when it declines to report
      // an unverifiable artifact as a merely newer one.
      final raw = candidate.stateVersion;

      return DriveStateImportResult.rejected(
        DriveStateOutcome.integrityFailed,
        'State-Version is ${raw == null ? 'absent' : '"$raw"'}, which is not '
        'a major.minor format version',
      );
    }
    if (taggedVersion.isNewerThanThisBuild) {
      return DriveStateImportResult.rejected(
        DriveStateOutcome.unknownVersion,
        'State-Version is $taggedVersion and this build reads '
        '${currentVersion.major}.x: the artifact is newer than this client',
      );
    }
    if (taggedVersion.isOlderThanThisBuild) {
      // Its own arm and its own sentence. Without it, what an older major
      // meets depends on the payload's shape and not on its version: a
      // missing-section refusal that describes a truncated payload rather
      // than an obsolete one, or no refusal at all.
      return DriveStateImportResult.rejected(
        DriveStateOutcome.unknownVersion,
        'State-Version is $taggedVersion and this build reads '
        '${currentVersion.major}.x: the artifact predates a breaking change '
        'to the format',
      );
    }

    // The envelope, built from the chain the tags say produced this artifact —
    // which step 1c has just established is the chain this drive's privacy
    // calls for. `DriveStateEnvelope` has no constructor that could hold a
    // cipher without its IV, so the two shapes below are the only two there
    // are.
    final DriveStateEnvelope envelope;
    if (artifactIsEncrypted) {
      final Uint8List iv;
      try {
        iv = utils.decodeBase64ToBytes(cipherIv!);
      } catch (e) {
        return DriveStateImportResult.rejected(
          DriveStateOutcome.integrityFailed,
          'the Cipher-IV tag is not base64: $e',
        );
      }

      // The `Cipher` tag verbatim, so a cipher this build does not read is
      // refused by the codec rather than assumed to be the one it does.
      envelope = DriveStateEnvelope.encrypted(
        body: body,
        cipherIv: iv,
        cipher: cipher,
      );
    } else {
      envelope = DriveStateEnvelope.inTheClear(body: body);
    }

    // 3. Signature first (§2.5). Nothing the payload claims is examined until
    //    the drive's owner is known to have signed it. For a public drive
    //    that check carries the whole weight: there is no key whose absence
    //    would have stopped a stranger's bytes here.
    final opened = await _codec.open(
      envelope: envelope,
      protection: protection,
      expectedOwnerAddress: expectedOwnerAddress,
    );

    if (opened.isFailed) {
      return DriveStateImportResult.rejected(
        opened.failure!.outcome,
        opened.reason!,
      );
    }

    // 4. Open the payload. It is a SQLite database, so the danger §2.4 warns
    //    about is real and is met head on rather than avoided: the file is
    //    attached read-only, `PRAGMA integrity_check` must pass, and its
    //    `sqlite_master` must match the frozen schema byte for byte — no
    //    views, no triggers, no virtual tables, no indexes, nothing but the
    //    eight tables this reader agreed to. Only then is a row read.
    //
    //    The rows then travel through the same [DriveStateExport] the JSON
    //    reader produced, so every guard below — identity, coverage, ghost
    //    folders, cycle detection, newer-row-wins — is the one that was
    //    already reviewed and tested. The container changed; the merge did
    //    not.
    if (!artifactSinkSupported) {
      return const DriveStateImportResult.rejected(
        DriveStateOutcome.integrityFailed,
        'this platform cannot open a drive state artifact yet',
      );
    }

    final DriveStateExport export;
    final source = await createArtifactSource(driveId, opened.plaintext!);
    try {
      await _driveDao.customStatement(
        'ATTACH DATABASE ? AS artifact',
        [source.path],
      );
      try {
        final refusal = await validateAttachedArtifact(
          _driveDao.attachedDatabase,
          alias: 'artifact',
        );
        if (refusal != null) {
          // Both arms are integrityFailed on purpose: §7's vocabulary
          // distinguishes *why a drive did not use its artifact*, and "the
          // bytes were not the thing they claimed" is one answer whether the
          // file was corrupt or carried a schema nobody agreed to. The detail
          // carries the distinction for the log.
          return DriveStateImportResult.rejected(
            DriveStateOutcome.integrityFailed,
            refusal.detail,
          );
        }
        export = await readArtifactAsExport(
          _driveDao.attachedDatabase,
          alias: 'artifact',
          blockStart: blockStart,
          blockEnd: blockEnd,
        );
      } finally {
        await _driveDao.customStatement('DETACH DATABASE artifact');
      }
    } catch (e) {
      return DriveStateImportResult.rejected(
        DriveStateOutcome.integrityFailed,
        'the payload is not a readable drive state container: $e',
      );
    } finally {
      await source.dispose();
    }

    // 5. Version agreement. Step 2 read the `State-Version` tag; this is the
    //    same claim from inside the signature, and the two have to match.
    //
    //    Exactly the shape `Block-Start`/`Block-End` already has, and settled
    //    the same way (§3.3): the tag is chosen by whoever posts the
    //    transaction and nobody signs it, the payload field is the owner's,
    //    and a reader that met them half way would be trusting the half
    //    anybody can rewrite. A correct producer cannot trip this — both come
    //    from [DriveStateFormatVersion.current] — so the only artifacts it
    //    turns away are ones whose tag was written by something other than the
    //    wallet that signed the body.
    //
    //    Any disagreement, including one only in the minor. "The minor changes
    //    nothing this reader dispatches on" is true and is not a reason to
    //    accept a tag that contradicts a signature; it is the reasoning §6.1
    //    is a case study in.
    //
    //    Not `unknownVersion`: nothing here says this client is old. It says
    //    the artifact's tag and its signed body disagree, which is
    //    [DriveStateOutcome.integrityFailed] — the payload did not match the
    //    shape its tags declared.
    if (export.version != taggedVersion) {
      return DriveStateImportResult.rejected(
        DriveStateOutcome.integrityFailed,
        'State-Version is tagged $taggedVersion and the signed payload '
        'declares ${export.version}',
      );
    }

    // 6. Identity. The tag names the drive; the payload has to agree, and so
    //    does every row in it. Without this an artifact could write rows into
    //    a drive nobody named — the one mistake a merge across a shared
    //    database must never make.
    final identity = _checkIdentity(
      export: export,
      driveId: driveId,
      protection: protection,
      expectedOwnerAddress: expectedOwnerAddress,
    );
    if (identity != null) return identity;

    // 7. `Entity-Count`. GCM proved the ciphertext arrived intact; this proves
    //    the body meant what the tags promised (§3.2). Decisive and cheap, and
    //    it runs before a single row is written.
    if (export.entityCount != declaredCount) {
      return DriveStateImportResult.rejected(
        DriveStateOutcome.countMismatch,
        'Entity-Count declared $declaredCount and the payload holds '
        '${export.entityCount} (${export.folders.length} folders, '
        '${export.files.length} files, 1 drive)',
      );
    }

    // 8. Coverage. The last of the claims a tag makes about the body, and the
    //    only one that sets a value the drive keeps after the import. Nothing
    //    signed said anything about coverage until it moved into the payload,
    //    so this is the check that stops an artifact's own bytes being
    //    re-published under a range their owner never claimed.
    //
    //    An absent `Block-Start` tag reads as 0, which is what every v1
    //    artifact publishes; a payload claiming otherwise is rejected rather
    //    than met half way.
    final coverage = export.coverage;
    if (coverage.blockEnd != blockEnd || coverage.blockStart != blockStart) {
      return DriveStateImportResult.rejected(
        DriveStateOutcome.coverageMismatch,
        'the tags claim coverage [$blockStart, $blockEnd] and the signed '
        'payload claims $coverage',
      );
    }

    final parseDuration = stopwatch.elapsed;

    return _merge(
      export: export,
      driveId: driveId,
      // The signed values, now that the tags are known to agree with them:
      // the watermark is set from what the owner signed, not from what a
      // transaction was labelled with.
      blockStart: coverage.blockStart,
      blockEnd: coverage.blockEnd,
      parseDuration: parseDuration,
      stopwatch: stopwatch..reset(),
    );
  }

  /// The four ways a payload can be about something other than the drive it
  /// was fetched for. Returns null when it is about the right one.
  DriveStateImportResult? _checkIdentity({
    required DriveStateExport export,
    required String driveId,
    required DriveStateProtection protection,
    required String expectedOwnerAddress,
  }) {
    if (export.drive.id != driveId) {
      return DriveStateImportResult.rejected(
        DriveStateOutcome.integrityFailed,
        'the Drive-Id tag says $driveId and the payload holds '
        '${export.drive.id}',
      );
    }

    // Every row of every section, not just the entry ones. A revision carries
    // its own `driveId` and is written by primary key, so a payload smuggling
    // one for another drive would rewrite that drive's history — the same
    // mistake as an entry row, on a table an importer is likelier to forget.
    for (final rowDriveId in [
      ...export.folders.map((f) => f.driveId),
      ...export.files.map((f) => f.driveId),
      ...export.driveRevisions.map((r) => r.driveId),
      ...export.folderRevisions.map((r) => r.driveId),
      ...export.fileRevisions.map((r) => r.driveId),
      ...export.licenses.map((l) => l.driveId),
    ]) {
      if (rowDriveId != driveId) {
        return DriveStateImportResult.rejected(
          DriveStateOutcome.integrityFailed,
          'the payload for $driveId carries rows belonging to $rowDriveId',
        );
      }
    }

    // The cipher/privacy cross-check again, one layer in: step 1c compared the
    // drive's privacy against what the *tags* claimed, and this compares it
    // against what the **signed payload** claims. They are different claims by
    // different authors, and this is the one that would be written to disk —
    // `_driveCompanion` copies the payload's `privacy` onto the local drive
    // row, so a payload that said `public` for a private drive would relabel
    // the user's own drive while its key material sat untouched beside it.
    //
    // Privacy is fixed when a drive is created and there is no way to change
    // it, so the two can only disagree if the artifact is not about this
    // drive, or the producer's own row is wrong. Neither is worth merging.
    final expectedPrivacy = protection.isEncrypted
        ? DrivePrivacyTag.private
        : DrivePrivacyTag.public;
    if (export.drive.privacy != expectedPrivacy) {
      return DriveStateImportResult.rejected(
        DriveStateOutcome.privacyMismatch,
        'the signed payload says drive $driveId is '
        '${export.drive.privacy}, and this client holds it as '
        '$expectedPrivacy',
      );
    }

    if (export.drive.ownerAddress != expectedOwnerAddress) {
      // The signature verified, so the owner really did publish this. Their
      // own drive row disagreeing with the address it verified against means
      // the payload is not internally consistent, and merging it would write
      // that disagreement into the database.
      return DriveStateImportResult.rejected(
        DriveStateOutcome.integrityFailed,
        'the payload names owner ${export.drive.ownerAddress} and the '
        'artifact verified against $expectedOwnerAddress',
      );
    }

    return null;
  }

  /// Everything that touches the database, in one transaction, after every
  /// check has passed.
  Future<DriveStateImportResult> _merge({
    required DriveStateExport export,
    required String driveId,
    required int blockStart,
    required int blockEnd,
    required Duration parseDuration,
    required Stopwatch stopwatch,
  }) {
    final drives = _driveDao.drives;
    final folderEntries = _driveDao.folderEntries;
    final fileEntries = _driveDao.fileEntries;

    return _driveDao.transaction(() async {
      final local = await (_driveDao.select(drives)
            ..where((d) => d.id.equals(driveId)))
          .getSingleOrNull();

      if (local == null) {
        // Import accelerates a drive the user already attached; it never
        // creates one. A drive row conjured here would have no key material,
        // which for a private drive is a drive nobody can open, and its
        // folders and files would be rows hanging off nothing.
        //
        // §7's vocabulary has no value for this because it should not happen:
        // the caller had to read this drive's key and owner address to get
        // here. It is coarse-grained as an integrity failure, and the detail
        // says what actually went wrong.
        return DriveStateImportResult.rejected(
          DriveStateOutcome.integrityFailed,
          'this client has no drive $driveId to import into',
        );
      }

      // No rollback (§2.5). An artifact covering less than what is already
      // synced can only take the drive backwards, so it is a no-op. Equal
      // coverage is still imported: the same range can hold entities a sync
      // skipped and this artifact has.
      final localWatermark = local.lastBlockHeight ?? 0;
      if (blockEnd < localWatermark) {
        return DriveStateImportResult.rejected(
          DriveStateOutcome.rangeAlreadyCovered,
          'the artifact\'s coverage ends at $blockEnd, below the drive\'s '
          '$localWatermark',
        );
      }

      final localFolders =
          await _lastUpdatedById(folderEntries, driveId: driveId);
      final localFiles = await _lastUpdatedById(fileEntries, driveId: driveId);

      // Which folder rows a revision vouches for, on each side. The payload's
      // half is read from the payload rather than assumed from the export's
      // filter: an importer checks what arrived, it does not trust the
      // producer to have run the code it was supposed to.
      final localVouchedFolders = await _folderIdsWithRevisions(driveId);
      final artifactVouchedFolders =
          export.folderRevisions.map((r) => r.folderId).toSet();

      // The drive's own row follows the same rule as every other row, and the
      // answer is needed here rather than at the write because it decides
      // which `rootFolderId` the drive ends the import with — which is the
      // one that has to resolve.
      final overwriteDriveMetadata =
          !local.lastUpdated.isAfter(export.drive.lastUpdated);
      final rootFolderId = overwriteDriveMetadata
          ? export.drive.rootFolderId
          : local.rootFolderId;

      final carriedFolderIds = export.folders.map((f) => f.id).toSet();

      /// Whether a folder id names a row that will exist when this merge ends,
      /// without anything being invented for it.
      bool resolves(String folderId) =>
          carriedFolderIds.contains(folderId) ||
          localFolders.containsKey(folderId);

      // The row graph, checked before the first write. A drive whose
      // `rootFolderId` names nothing cannot be opened at all, and this is the
      // one such row that must not be materialised: see the class comment.
      // Only checked when the payload's value is the one being adopted — a
      // local `rootFolderId` that resolves nowhere is this client's own
      // pre-existing defect, and refusing an artifact over it would decline
      // the very thing that could repair the drive.
      if (overwriteDriveMetadata && !resolves(rootFolderId)) {
        return DriveStateImportResult.rejected(
          DriveStateOutcome.integrityFailed,
          'the payload\'s drive row names root folder $rootFolderId, which no '
          'section carries and this client does not hold',
        );
      }

      var kept = 0;

      bool artifactWins(
        String id,
        DateTime lastUpdated,
        Map<String, DateTime> known, {
        bool localRowIsAStandIn = false,
      }) {
        final localLastUpdated = known[id];
        if (localLastUpdated == null) return true;
        if (localRowIsAStandIn) return true;
        if (localLastUpdated.isAfter(lastUpdated)) {
          kept++;
          return false;
        }
        return true;
      }

      final folders = export.folders
          .where((f) => artifactWins(
                f.id,
                f.lastUpdated,
                localFolders,
                localRowIsAStandIn: _folderStandInLoses(
                  folderId: f.id,
                  artifactVouched: artifactVouchedFolders,
                  localVouched: localVouchedFolders,
                ),
              ))
          .toList();

      final files = export.files
          .where((f) => artifactWins(f.id, f.lastUpdated, localFiles))
          .toList();

      final folderRows = folders.map(_folderCompanion).toList();
      final fileRows = files.map(_fileCompanion).toList();

      // Every parent this merge is about to write, that resolves nowhere.
      final unresolvedParents = <String>{
        ...folders.map((f) => f.parentFolderId).whereType<String>(),
        ...files.map((f) => f.parentFolderId),
      }..removeWhere(resolves);

      // A stand-in is parented to the drive's root folder, exactly as
      // `SyncRepository.createGhosts` parents one - so the root has to resolve
      // too, or the stand-in is an orphan of the kind it was written to fix.
      // Only reachable when the payload's `rootFolderId` was *not* adopted:
      // the guard above refuses the case where it was.
      if (unresolvedParents.isNotEmpty && !resolves(rootFolderId)) {
        unresolvedParents.add(rootFolderId);
      }

      final standInFolderRows = unresolvedParents
          .map((id) => id == rootFolderId
              ? _rootFolderStandIn(
                  driveId: driveId,
                  rootFolderId: id,
                  name: export.drive.name,
                )
              : _ghostFolderStandIn(
                  driveId: driveId,
                  folderId: id,
                  parentFolderId: rootFolderId,
                ))
          .toList();

      // Closure is not acyclicity.
      //
      // Every `parentFolderId` now resolves, but `A -> B -> A` resolves too,
      // and `DriveDao.getFolderTree` recurses on `parentFolderId` with no
      // depth bound: a cycle hangs drive size, folder download, manifests and
      // share-folder selection, permanently, because the same payload
      // re-applies on every sync once `blockEnd == localWatermark`.
      //
      // Chain data cannot produce one — a folder's parent is fixed by its
      // metadata and history only moves forward — so this is a check against a
      // payload that was malformed or built by a broken producer. That is
      // exactly the case the threat model keeps: an artifact is authentic,
      // permanent, and cannot be recalled.
      //
      // Local parents are read too, because a cycle does not have to live
      // wholly inside the payload: re-parenting one carried folder onto a
      // local folder whose own ancestor is that carried folder closes a loop
      // out of two individually innocent rows.
      final localParents = await _parentFolderIdById(driveId);
      final effectiveParents = <String, String?>{
        ...localParents,
        for (final row in standInFolderRows)
          row.id.value: row.parentFolderId.value,
        for (final folder in folders) folder.id: folder.parentFolderId,
      };

      final cycle = _firstFolderCycle(effectiveParents);
      if (cycle != null) {
        return DriveStateImportResult.rejected(
          DriveStateOutcome.integrityFailed,
          'the folder graph this payload would leave behind contains a cycle: '
          '${cycle.join(' -> ')}',
        );
      }

      // The revisions the entries above are versions of, and the licences
      // attached to them. Built before the write because the derivation of
      // `network_transactions` reads them.
      final driveRevisionRows =
          export.driveRevisions.map(_driveRevisionCompanion).toList();
      final folderRevisionRows =
          export.folderRevisions.map(_folderRevisionCompanion).toList();
      final fileRevisionRows =
          export.fileRevisions.map(_fileRevisionCompanion).toList();
      final licenseRows = export.licenses.map(_licenseCompanion).toList();

      // `network_transactions` is derived, never carried: it has no `driveId`
      // to scope it by, so publishing it would publish rows about the user's
      // other drives to everyone holding this drive's key. These are the same
      // helpers `SyncRepository` derives it with, so there is one derivation
      // with one set of tests rather than a second one here that drifts.
      final transactionRows = [
        ...createNetworkTransactionsCompanionsForDrives(driveRevisionRows),
        ...createNetworkTransactionsCompanionsForFolders(folderRevisionRows),
        ...createNetworkTransactionsCompanionsForFiles(fileRevisionRows),
        // A licence transaction is not derivable from a revision - a composed
        // licence shares the data transaction's id, an assertion has its own -
        // so it comes from the licence row, through the same single place the
        // rest of the app derives it: `LicensesCompanionExtensions`.
        ...licenseRows.expand((l) => l.getTransactionCompanions()),
      ].map(_asMined).toList();

      final revisionsBefore = await _revisionRowCount(driveId);
      final licensesBefore = await _rowCount(_driveDao.licenses, driveId);
      final transactionsBefore = await _transactionRowCount();

      await _driveDao.batch((b) {
        // Transactions first: the revision tables carry foreign keys onto
        // them. SQLite is not enforcing those here - no `PRAGMA foreign_keys`
        // is set - but writing in an order that would satisfy them if it were
        // costs nothing and stops this being the statement that breaks the day
        // somebody turns them on.
        b.insertAll(
          _driveDao.networkTransactions,
          transactionRows,
          mode: InsertMode.insertOrIgnore,
        );
        b.insertAll(
          _driveDao.driveRevisions,
          driveRevisionRows,
          mode: InsertMode.insertOrIgnore,
        );
        b.insertAll(
          _driveDao.folderRevisions,
          folderRevisionRows,
          mode: InsertMode.insertOrIgnore,
        );
        b.insertAll(
          _driveDao.fileRevisions,
          fileRevisionRows,
          mode: InsertMode.insertOrIgnore,
        );
        b.insertAll(
          _driveDao.licenses,
          licenseRows,
          mode: InsertMode.insertOrIgnore,
        );
        b.insertAllOnConflictUpdate(folderEntries, folderRows);
        // `insertOrIgnore`, never an upsert: a stand-in is this client's guess
        // and must lose to anything real, including a row another statement in
        // this same batch landed.
        b.insertAll(
          folderEntries,
          standInFolderRows,
          mode: InsertMode.insertOrIgnore,
        );
        b.insertAllOnConflictUpdate(fileEntries, fileRows);
      });

      // Counted rather than assumed. `insertOrIgnore` leaves a row the client
      // already had alone, so the number of rows offered is not the number of
      // rows landed, and the log line §7 asks for is about what changed.
      final revisionsWritten =
          await _revisionRowCount(driveId) - revisionsBefore;
      final licensesWritten =
          await _rowCount(_driveDao.licenses, driveId) - licensesBefore;
      final transactionsWritten =
          await _transactionRowCount() - transactionsBefore;

      // The watermark advances only across ground the artifact actually
      // covers. The coverage starts at 0 for everything this client publishes,
      // so in practice this is always `blockEnd`; it is checked because a
      // future producer's incremental artifact would otherwise move the
      // watermark over a range nobody synced.
      final watermark =
          blockStart <= localWatermark ? blockEnd : localWatermark;

      await (_driveDao.update(drives)..where((d) => d.id.equals(driveId)))
          .write(
        _driveCompanion(
          export.drive,
          watermark: watermark,
          overwriteMetadata: overwriteDriveMetadata,
        ),
      );

      return DriveStateImportResult.imported(
        DriveStateImportStats(
          foldersWritten: folderRows.length,
          foldersMaterialised: standInFolderRows.length,
          filesWritten: fileRows.length,
          revisionsWritten: revisionsWritten,
          licensesWritten: licensesWritten,
          transactionsWritten: transactionsWritten,
          rowsKeptLocallyNewer: kept,
          watermark: watermark,
          parseDuration: parseDuration,
          mergeDuration: stopwatch.elapsed,
        ),
      );
    });
  }

  /// `id -> lastUpdated` for one drive's rows, which is everything the merge
  /// needs to know about what is already there. Reading whole rows to compare
  /// one column would be the same query and a great deal more memory.
  /// `parentFolderId` for every folder this drive already holds.
  ///
  /// Read separately from [_lastUpdatedById] rather than widening it, because
  /// only the cycle check needs parents and every other caller would carry the
  /// column for nothing.
  Future<Map<String, String?>> _parentFolderIdById(String driveId) async {
    final folders = _driveDao.folderEntries;

    final rows = await (_driveDao.selectOnly(folders)
          ..addColumns([folders.id, folders.parentFolderId])
          ..where(folders.driveId.equals(driveId)))
        .get();

    return {
      for (final row in rows)
        row.read(folders.id)!: row.read(folders.parentFolderId),
    };
  }

  Future<Map<String, DateTime>> _lastUpdatedById(
    TableInfo table, {
    required String driveId,
  }) async {
    final id = table.columnsByName['id']! as GeneratedColumn<String>;
    final lastUpdated =
        table.columnsByName['lastUpdated']! as GeneratedColumn<DateTime>;
    final owner = table.columnsByName['driveId']! as GeneratedColumn<String>;

    final rows = await (_driveDao.selectOnly(table)
          ..addColumns([id, lastUpdated])
          ..where(owner.equals(driveId)))
        .get();

    return {
      for (final row in rows) row.read(id)!: row.read(lastUpdated)!,
    };
  }

  /// The folder ids this database holds a `folder_revisions` row for.
  ///
  /// The local half of [_folderStandInLoses]. Read as a set of ids rather than
  /// as an existence check per contested row, because the contested rows are
  /// counted in tens of thousands and this is one statement either way.
  Future<Set<String>> _folderIdsWithRevisions(String driveId) async {
    final revisions = _driveDao.folderRevisions;

    final rows = await (_driveDao.selectOnly(revisions, distinct: true)
          ..addColumns([revisions.folderId])
          ..where(revisions.driveId.equals(driveId)))
        .get();

    return {for (final row in rows) row.read(revisions.folderId)!};
  }

  /// How many rows [table] holds for one drive.
  Future<int> _rowCount(TableInfo table, String driveId) async {
    final owner = table.columnsByName['driveId']! as GeneratedColumn<String>;
    final count = countAll();

    final row = await (_driveDao.selectOnly(table)
          ..addColumns([count])
          ..where(owner.equals(driveId)))
        .getSingle();

    return row.read(count)!;
  }

  /// All three revision tables together, which is how the log reports them.
  Future<int> _revisionRowCount(String driveId) async =>
      await _rowCount(_driveDao.driveRevisions, driveId) +
      await _rowCount(_driveDao.folderRevisions, driveId) +
      await _rowCount(_driveDao.fileRevisions, driveId);

  /// How many rows `network_transactions` holds, in total.
  ///
  /// The whole table, not the ids this import is about. It has no `driveId` to
  /// filter on, and the obvious alternative — `id IN (every id the revisions
  /// name)` — is a variable per id: on the 42,000 file drive this feature was
  /// measured against that is upwards of 84,000 of them, well past SQLite's
  /// `SQLITE_MAX_VARIABLE_NUMBER`, and it would turn a statistic into the
  /// thing that fails the import.
  ///
  /// Taking the difference across the write inside the merge's own transaction
  /// gives the same answer for free: no other statement runs between the two
  /// reads, so every row that appeared is one this import inserted.
  Future<int> _transactionRowCount() async {
    final count = countAll();

    final row = await (_driveDao.selectOnly(_driveDao.networkTransactions)
          ..addColumns([count]))
        .getSingle();

    return row.read(count)!;
  }
}

/// The drive's non-key columns, plus the watermark the tags dictate.
///
/// `encryptedKey`, `driveKeyGenerated`, `keyEncryptionIv` and `syncCursor` are
/// absent, so the update statement never mentions them and the local values
/// survive. That is not an omission to tidy up later: an import that nulled a
/// private drive's key would lock the user out of their own drive.
DrivesCompanion _driveCompanion(
  ExportedDrive drive, {
  required int watermark,
  required bool overwriteMetadata,
}) {
  final watermarkOnly = DrivesCompanion(lastBlockHeight: Value(watermark));

  if (!overwriteMetadata) return watermarkOnly;

  return watermarkOnly.copyWith(
    rootFolderId: Value(drive.rootFolderId),
    ownerAddress: Value(drive.ownerAddress),
    name: Value(drive.name),
    privacy: Value(drive.privacy),
    bundledIn: Value(drive.bundledIn),
    customJsonMetadata: Value(drive.customJsonMetadata),
    customGQLTags: Value(drive.customGQLTags),
    isHidden: Value(drive.isHidden),
    signatureType: Value(drive.signatureType),
    dateCreated: Value(drive.dateCreated),
    lastUpdated: Value(drive.lastUpdated),
  );
}

/// Every column of `folder_entries`, named. A row is written whole or not at
/// all, so a column the artifact carries as null lands as null rather than
/// leaving a stale local value behind.
FolderEntriesCompanion _folderCompanion(ExportedFolderEntry folder) =>
    FolderEntriesCompanion(
      id: Value(folder.id),
      driveId: Value(folder.driveId),
      name: Value(folder.name),
      parentFolderId: Value(folder.parentFolderId),
      path: Value(folder.path),
      dateCreated: Value(folder.dateCreated),
      lastUpdated: Value(folder.lastUpdated),
      isGhost: Value(folder.isGhost),
      customJsonMetadata: Value(folder.customJsonMetadata),
      customGQLTags: Value(folder.customGQLTags),
      isHidden: Value(folder.isHidden),
    );

/// Whether the local `folder_entries` row for [folderId] is a stand-in that
/// must give way to the artifact's copy whatever the two timestamps say.
///
/// The merge's ordinary rule is *the newer `lastUpdated` wins*, and for a
/// folder that rule is decided against a number the consumer made up. This
/// client fabricates exactly two kinds of `folder_entries` row, and both are
/// stamped with the moment they were written rather than with anything from
/// the chain:
///
///  * a **ghost**, when a file names a parent whose own metadata was never
///    read (`SyncRepository.createGhosts`, `DateTime.now()`);
///  * a **root folder placeholder**, so a drive can be opened before its root
///    folder metadata arrives (`DriveDao._rootFolderPlaceholder`, which sets
///    no timestamp and so takes SQLite's `strftime('%s','now')`).
///
/// The artifact's genuine row carries its revision's chain commit time, which
/// is older by construction. So the timestamp comparison hands every one of
/// these contests to the stand-in, permanently: the artifact is immutable, and
/// the import advances the watermark past the range whose metadata would have
/// let sync heal it. A drive keeps a uuid-named folder parented to its root
/// and can never be told the real name.
///
/// The discriminator is the one the export already uses in the other
/// direction (`_folderEntryCameFromChain`): a revision is written only when
/// real metadata was read, so a row with no revision behind it is a guess. A
/// row the artifact vouches for with a revision therefore beats a local row
/// nothing vouches for — and nothing else changes, so a genuine local row that
/// is newer still wins, and equal ages still go to the artifact.
///
/// **Scoped to `folder_entries` on purpose.** The mirror rule for files would
/// be wrong: no code path fabricates a `file_entries` row (the same conclusion
/// `_fileEntryCameFromChain` records), so an unvouched local file row is not a
/// stand-in — it is an ordinary row whose revision this client has yet to
/// write. Overwriting it would undo a local rename or a local upload. The
/// asymmetry with the export is deliberate: over-applying the filter there
/// omits a row from a payload, over-applying it here destroys one.
bool _folderStandInLoses({
  required String folderId,
  required Set<String> artifactVouched,
  required Set<String> localVouched,
}) =>
    artifactVouched.contains(folderId) && !localVouched.contains(folderId);

/// A stand-in for a folder the payload's rows name as a parent and no section
/// carries.
///
/// The same row `SyncRepository.createGhosts` writes, deliberately: named
/// after its own uuid, parented to the drive root, `isGhost: true`, stamped
/// now. Matching it is the whole point — the ghost UI, the **Fix** flow and
/// the sync path that later replaces the row all key off exactly this shape,
/// and a second kind of placeholder would need a second set of all three.
///
/// The consumer therefore ends up where the producer already is: a ghost
/// folder with a Fix button, holding its files. Without it the files are in
/// the database and in no folder — nothing in this app lists a file except by
/// its parent — and no later sync repairs them, because the import moved the
/// watermark past the metadata that registered the ghost in the first place.
///
/// Parenting every stand-in at the drive root, rather than at whatever named
/// it, is also `createGhosts`' behaviour and is what makes this terminate: a
/// stand-in introduces no new unresolved parent, so one pass closes a graph of
/// any depth — a ghost inside a ghost included.
FolderEntriesCompanion _ghostFolderStandIn({
  required String driveId,
  required String folderId,
  required String parentFolderId,
}) =>
    FolderEntriesCompanion.insert(
      id: folderId,
      driveId: driveId,
      parentFolderId: Value(parentFolderId),
      name: folderId,
      path: '',
      isGhost: const Value(true),
      isHidden: const Value(false),
      dateCreated: Value(DateTime.now()),
      lastUpdated: Value(DateTime.now()),
    );

/// A stand-in for the drive's own root folder.
///
/// `DriveDao._rootFolderPlaceholder`'s row, for its reasons: **not** marked
/// `isGhost`, because the upsert that lands the real metadata leaves absent
/// columns alone and the flag would stick for ever; and with no
/// `parentFolderId`, because [_ghostFolderStandIn] points a stand-in at the
/// drive root, which for the root itself would be a self-reference. That is
/// also why `createGhosts` excludes root folders.
///
/// Only reached when the drive is keeping its *own* `rootFolderId` — the
/// payload's is refused when it resolves nowhere, rather than materialised.
FolderEntriesCompanion _rootFolderStandIn({
  required String driveId,
  required String rootFolderId,
  required String name,
}) =>
    FolderEntriesCompanion.insert(
      id: rootFolderId,
      driveId: driveId,
      name: name,
      isHidden: const Value(false),
      path: '',
    );

/// Every column of `drive_revisions`, named.
DriveRevisionsCompanion _driveRevisionCompanion(ExportedDriveRevision rev) =>
    DriveRevisionsCompanion(
      driveId: Value(rev.driveId),
      rootFolderId: Value(rev.rootFolderId),
      ownerAddress: Value(rev.ownerAddress),
      name: Value(rev.name),
      privacy: Value(rev.privacy),
      metadataTxId: Value(rev.metadataTxId),
      dateCreated: Value(rev.dateCreated),
      action: Value(rev.action),
      bundledIn: Value(rev.bundledIn),
      customJsonMetadata: Value(rev.customJsonMetadata),
      customGQLTags: Value(rev.customGQLTags),
      isHidden: Value(rev.isHidden),
    );

/// Every column of `folder_revisions`, named.
FolderRevisionsCompanion _folderRevisionCompanion(ExportedFolderRevision rev) =>
    FolderRevisionsCompanion(
      folderId: Value(rev.folderId),
      driveId: Value(rev.driveId),
      name: Value(rev.name),
      parentFolderId: Value(rev.parentFolderId),
      metadataTxId: Value(rev.metadataTxId),
      dateCreated: Value(rev.dateCreated),
      action: Value(rev.action),
      customJsonMetadata: Value(rev.customJsonMetadata),
      customGQLTags: Value(rev.customGQLTags),
      isHidden: Value(rev.isHidden),
    );

/// Every column of `file_revisions`, named.
FileRevisionsCompanion _fileRevisionCompanion(ExportedFileRevision rev) =>
    FileRevisionsCompanion(
      fileId: Value(rev.fileId),
      driveId: Value(rev.driveId),
      name: Value(rev.name),
      parentFolderId: Value(rev.parentFolderId),
      size: Value(rev.size),
      lastModifiedDate: Value(rev.lastModifiedDate),
      dataContentType: Value(rev.dataContentType),
      metadataTxId: Value(rev.metadataTxId),
      dataTxId: Value(rev.dataTxId),
      licenseTxId: Value(rev.licenseTxId),
      thumbnail: Value(rev.thumbnail),
      bundledIn: Value(rev.bundledIn),
      dateCreated: Value(rev.dateCreated),
      customJsonMetadata: Value(rev.customJsonMetadata),
      customGQLTags: Value(rev.customGQLTags),
      action: Value(rev.action),
      pinnedDataOwnerAddress: Value(rev.pinnedDataOwnerAddress),
      isHidden: Value(rev.isHidden),
      assignedNames: Value(rev.assignedNames),
      fallbackTxId: Value(rev.fallbackTxId),
      originalOwner: Value(rev.originalOwner),
      importSource: Value(rev.importSource),
    );

/// Every column of `licenses`, named.
LicensesCompanion _licenseCompanion(ExportedLicense license) =>
    LicensesCompanion(
      fileId: Value(license.fileId),
      driveId: Value(license.driveId),
      dataTxId: Value(license.dataTxId),
      licenseTxType: Value(license.licenseTxType),
      licenseTxId: Value(license.licenseTxId),
      bundledIn: Value(license.bundledIn),
      dateCreated: Value(license.dateCreated),
      licenseType: Value(license.licenseType),
      customGQLTags: Value(license.customGQLTags),
    );

/// A derived `network_transactions` row, marked as what it is: mined.
///
/// The sync helpers set a file's **data** transaction to `pending`, and they
/// are right to. Sync writes a revision the moment it reads the metadata, and
/// the metadata can be on chain before the data it points at is — so sync
/// leaves the data transaction to be confirmed by a later pass, which is what
/// `_updateTransactionStatuses` is for.
///
/// An import is not that situation. These rows arrive inside an artifact whose
/// signed coverage claim is the producer's own sync watermark: the producer
/// had walked the chain to `Block-End` and these are the transactions it read
/// there. Carrying them over as `pending` would do two things, both bad and
/// both certain, to buy a distinction the payload cannot make anyway:
///
///  * every file in a restored drive would render with the pending icon
///    (`fileStatusFromTransactions`) until something confirmed it;
///  * and that something is a per-transaction gateway query — on a 42,000 file
///    drive, 42,000 of them, which is precisely the work the artifact exists
///    to avoid. An artifact that imported in one decryption and then triggered
///    a full confirmation sweep would have saved nothing.
///
/// The residual case is wider than "still unmined", and it is worth stating
/// exactly, because the export joins nothing to `network_transactions`: a
/// revision travels whatever status the producer held for it. So this confirms
/// every transaction the producer had **not** confirmed at publication —
/// `pending`, and `failed` too. A consumer shows those files as confirmed and
/// finds out at download time, and nothing re-checks: `pendingTransactions`
/// (`lib/models/queries/drive_queries.drift`) selects `status = 'pending'`
/// only, so a row written straight to `confirmed` is never revisited.
///
/// Narrowing it would have to happen in the export, by not publishing a
/// revision whose transaction this client calls `failed`, and that is worse
/// than the wrong status. `failed` is not an authority: `SyncRepository
/// ._updateTransactionStatuses` sets it when a gateway reported the id
/// not-found for longer than a threshold, which a gateway can do about a
/// transaction that is perfectly well on chain. Dropping such rows would omit
/// real files from the payload while the import still advances the watermark
/// past the range their metadata lives in — turning a wrong icon into a file
/// the consumer can never see. That is the failure this file's row-graph
/// section exists to prevent, arrived at from the other side.
///
/// So the row travels and its status is the thing that is wrong, deliberately:
/// a recoverable wrong answer about the producer's own unconfirmed uploads,
/// against a wrong answer about every file in the drive, every time.
///
/// The true statuses are in the producer's `network_transactions`, which
/// cannot travel: it has no `driveId`, so publishing it would publish rows
/// about the user's other drives to everyone holding this drive's key.
/// The first `parentFolderId` cycle in [parents], as the path around it, or
/// null if the graph is acyclic.
///
/// One pass with three colours rather than a walk per folder: at 42,000
/// folders the per-folder walk is quadratic in the depth of the tree, and this
/// runs on every import. A node already proven acyclic is never re-entered.
///
/// A parent that is absent from [parents] terminates a chain rather than
/// failing it. Absence here means "no row will exist for it", which the
/// closure check immediately above has already refused; treating it as a
/// second failure would report a cycle for a graph that has none.
List<String>? _firstFolderCycle(Map<String, String?> parents) {
  const onStack = 1, settled = 2;
  final state = <String, int>{};

  for (final start in parents.keys) {
    if (state[start] == settled) continue;

    // Iterative, because a drive's folder tree is user-shaped: nothing stops
    // it being deep enough to overflow the stack, and a payload built to do
    // exactly that is the case this function exists for.
    final path = <String>[];

    String? current = start;
    while (current != null && state[current] != settled) {
      if (state[current] == onStack) {
        return [...path.sublist(path.indexOf(current)), current];
      }

      state[current] = onStack;
      path.add(current);
      current = parents.containsKey(current) ? parents[current] : null;
    }

    for (final id in path) {
      state[id] = settled;
    }
  }

  return null;
}

NetworkTransactionsCompanion _asMined(NetworkTransactionsCompanion tx) =>
    tx.copyWith(status: const Value(TransactionStatus.confirmed));

/// Every column of `file_entries`, named.
FileEntriesCompanion _fileCompanion(ExportedFileEntry file) =>
    FileEntriesCompanion(
      id: Value(file.id),
      driveId: Value(file.driveId),
      name: Value(file.name),
      parentFolderId: Value(file.parentFolderId),
      path: Value(file.path),
      size: Value(file.size),
      lastModifiedDate: Value(file.lastModifiedDate),
      dataContentType: Value(file.dataContentType),
      dataTxId: Value(file.dataTxId),
      licenseTxId: Value(file.licenseTxId),
      bundledIn: Value(file.bundledIn),
      thumbnail: Value(file.thumbnail),
      pinnedDataOwnerAddress: Value(file.pinnedDataOwnerAddress),
      customJsonMetadata: Value(file.customJsonMetadata),
      customGQLTags: Value(file.customGQLTags),
      isHidden: Value(file.isHidden),
      dateCreated: Value(file.dateCreated),
      lastUpdated: Value(file.lastUpdated),
      assignedNames: Value(file.assignedNames),
      fallbackTxId: Value(file.fallbackTxId),
      originalOwner: Value(file.originalOwner),
      importSource: Value(file.importSource),
    );
