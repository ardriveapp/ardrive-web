import 'dart:convert';

import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/drive_state/domain/drive_state_entity.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/models/license.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/utils/network_transaction_utils.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show EntityTag;
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart' show SecretKey;
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
      'kept-local=$rowsKeptLocallyNewer) '
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
  /// The codec distinguishes eleven ways an artifact can be unreadable because
  /// it is the layer that can tell them apart. A reader of a sync log wants
  /// the answer to *why did this drive not use its artifact*, and eleven
  /// shades of "it did not open" would bury it — so §7's vocabulary is coarser
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
///  * the revision tables and `licenses` obey the same rule, arrived at
///    differently. Their primary keys *contain* their version — a revision is
///    keyed by `(entityId, driveId, dateCreated)` — so a newer copy of a row
///    is not a conflicting write, it is a different key. There is therefore
///    nothing for a `lastUpdated` comparison to decide: the artifact can only
///    add, and a row the client already holds is left exactly as it is. That
///    is what [InsertMode.insertOrIgnore] says, and it is strictly the safer
///    half of the same policy;
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

  /// Opens [body] — the artifact transaction's data — under [driveKey], checks
  /// it was signed by [expectedOwnerAddress], and merges it into the drive
  /// named by [candidate]'s `Drive-Id` tag.
  ///
  /// [candidate] is the discovery lane's product: a transaction id and the
  /// tags an untrusted indexer reported for it. Nothing it says is believed
  /// here either — the tags are what the payload is checked *against*, which
  /// is the only reason they are worth having.
  ///
  /// Never throws.
  Future<DriveStateImportResult> import({
    required DriveStateArtifactCandidate candidate,
    required Uint8List body,
    required SecretKey driveKey,
    required String expectedOwnerAddress,
  }) async {
    try {
      return await _import(
        candidate: candidate,
        body: body,
        driveKey: driveKey,
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
    required SecretKey driveKey,
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

    if (driveId == null ||
        blockEnd == null ||
        declaredCount == null ||
        cipher == null ||
        cipherIv == null) {
      return DriveStateImportResult.rejected(
        DriveStateOutcome.integrityFailed,
        'a required tag is missing or unreadable on ${candidate.txId}: '
        'Drive-Id=$driveId Block-End=${candidate.tag(EntityTag.blockEnd)} '
        'Entity-Count=${candidate.tag(EntityTag.entityCount)} '
        'Cipher=$cipher Cipher-IV=${cipherIv == null ? 'absent' : 'set'}',
      );
    }

    // 2. `State-Version`. A version this build does not know is skipped, never
    //    guessed at (§6).
    final stateVersion = int.tryParse(candidate.stateVersion ?? '');
    if (stateVersion != DriveStateEntity.currentStateVersion) {
      return DriveStateImportResult.rejected(
        DriveStateOutcome.unknownVersion,
        'State-Version is ${candidate.stateVersion}, and this build reads '
        '${DriveStateEntity.currentStateVersion}',
      );
    }

    final Uint8List iv;
    try {
      iv = utils.decodeBase64ToBytes(cipherIv);
    } catch (e) {
      return DriveStateImportResult.rejected(
        DriveStateOutcome.integrityFailed,
        'the Cipher-IV tag is not base64: $e',
      );
    }

    // 3. Signature first (§2.5). Nothing the payload claims is examined until
    //    the drive's owner is known to have signed it.
    final opened = await _codec.open(
      envelope: DriveStateEnvelope(body: body, cipherIv: iv, cipher: cipher),
      driveKey: driveKey,
      expectedOwnerAddress: expectedOwnerAddress,
    );

    if (opened.isFailed) {
      return DriveStateImportResult.rejected(
        opened.failure!.outcome,
        opened.reason!,
      );
    }

    // 4. Parse. Untrusted bytes reach a JSON decoder and a typed projection,
    //    and never SQLite directly (§2.4).
    final DriveStateExport export;
    try {
      export = DriveStateExport.fromJson(
        jsonDecode(utf8.decode(opened.plaintext!)) as Map<String, dynamic>,
      );
    } on DriveStateFormatException catch (e) {
      return DriveStateImportResult.rejected(
        e.error == DriveStateFormatError.unsupportedVersion
            ? DriveStateOutcome.unknownVersion
            : DriveStateOutcome.integrityFailed,
        e.message,
      );
    } catch (e) {
      return DriveStateImportResult.rejected(
        DriveStateOutcome.integrityFailed,
        'the payload is not a readable drive state container: $e',
      );
    }

    // 5. Identity. The tag names the drive; the payload has to agree, and so
    //    does every row in it. Without this an artifact could write rows into
    //    a drive nobody named — the one mistake a merge across a shared
    //    database must never make.
    final identity = _checkIdentity(
      export: export,
      driveId: driveId,
      expectedOwnerAddress: expectedOwnerAddress,
    );
    if (identity != null) return identity;

    // 6. `Entity-Count`. GCM proved the ciphertext arrived intact; this proves
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

    // 7. Coverage. The last of the claims a tag makes about the body, and the
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

  /// The three ways a payload can be about something other than the drive it
  /// was fetched for. Returns null when it is about the right one.
  DriveStateImportResult? _checkIdentity({
    required DriveStateExport export,
    required String driveId,
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

      var kept = 0;

      bool artifactWins(
        String id,
        DateTime lastUpdated,
        Map<String, DateTime> known,
      ) {
        final localLastUpdated = known[id];
        if (localLastUpdated != null && localLastUpdated.isAfter(lastUpdated)) {
          kept++;
          return false;
        }
        return true;
      }

      final folderRows = export.folders
          .where((f) => artifactWins(f.id, f.lastUpdated, localFolders))
          .map(_folderCompanion)
          .toList();

      final fileRows = export.files
          .where((f) => artifactWins(f.id, f.lastUpdated, localFiles))
          .map(_fileCompanion)
          .toList();

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
          // The drive's own row follows the same rule as every other row.
          overwriteMetadata:
              !local.lastUpdated.isAfter(export.drive.lastUpdated),
        ),
      );

      return DriveStateImportResult.imported(
        DriveStateImportStats(
          foldersWritten: folderRows.length,
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
/// The residual case is a producer that published while one of its own uploads
/// was still unmined. Its consumer would show that one file as confirmed when
/// it is not, and find out at download time. That is a narrow and recoverable
/// wrong answer; the alternative is a wrong answer about every file in the
/// drive, every time.
///
/// The true statuses are in the producer's `network_transactions`, which
/// cannot travel: it has no `driveId`, so publishing it would publish rows
/// about the user's other drives to everyone holding this drive's key.
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
