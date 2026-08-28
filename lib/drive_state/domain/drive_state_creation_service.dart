
import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/drive_state/domain/drive_state_entity.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/drive_state_sqlite/artifact_sink.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart'
    as sqlite;
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart';
import 'package:ardrive/models/models.dart';
import 'package:arweave/arweave.dart' show Wallet;
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:uuid/uuid.dart';

/// Preparing one drive's state artifact — and refusing to.
///
/// This service does **not** upload. It returns a [DriveStateEntity] with its
/// body sealed and its tags set, ready for a transaction or a data item, and
/// stops there. Publishing costs money and is permanent, so it is the user's
/// action and nobody else's: `docs/drive-state/DECISIONS.md` D3 (explicit user
/// action only) and D8 (the loop never uploads). There is no upload
/// collaborator on this class to call by accident.
///
/// ## The precondition that matters
///
/// A sync that reported skipped entities must never produce an artifact
/// (`docs/DRIVE_STATE_ARTIFACT.md` §5). Sync advances a drive's
/// `lastBlockHeight` whether or not it managed to read every entity in the
/// range — the failure `docs/SYNC_SKIPPED_ENTITY_PERSISTENCE.md` describes —
/// so an artifact produced from that state declares coverage it does not have.
/// An importer trusting its `Block-End` skips the range the gap is in, and
/// because Arweave has no delete, the gap is permanent and every future
/// reader inherits it.
///
/// So the first thing this service does is ask, and it refuses on anything
/// short of a positive answer. [DriveStateSyncSkipStatus] has three values,
/// not two, exactly so that "cannot tell" is refusable rather than roundable
/// down to "clean".
enum DriveStateCreationRefusal {
  /// The last sync of this drive left entities out. The D3 refusal.
  syncSkippedEntities,

  /// Whether this drive is complete cannot be established. Refused for the
  /// same reason as [syncSkippedEntities]: an unprovable claim published
  /// immutably is the same failure, arrived at less honestly.
  skipStateUnknown,

  /// No such drive in the local database.
  driveNotFound,

  /// How this drive's artifact would be protected could not be established:
  /// a private drive whose key is not available, a public drive a key was
  /// somehow supplied for, or a `privacy` column holding neither value.
  ///
  /// One refusal for the three because they are one situation from the user's
  /// side — this drive's state cannot be sealed right now — and because the
  /// alternative is a menu of refusals for two states that should not occur.
  /// Which of the three it was is in
  /// [DriveStateProtectionResult.reason], which becomes this refusal's
  /// sentence verbatim.
  ///
  /// Public drives are *not* refused. They publish an artifact that is signed
  /// and not encrypted; see [DriveStateProtection].
  protectionUnavailable,

  /// The signing wallet is not the drive's owner. The artifact would be sealed
  /// with a signature every importer rejects (`ownerMismatch`), so the money
  /// would buy an artifact nothing can use.
  notDriveOwner,

  /// The drive has no sync watermark, so there is no honest `Block-End` to
  /// declare. Coverage is what an importer adopts; a claim of none is not
  /// worth publishing.
  noWatermark,

  /// The payload is at or above
  /// [DriveStateEnvelopeCodec.defaultMaxPlaintextBytes]. D5: refuse rather
  /// than split. The bound is on the producer's memory, so it applies to a
  /// public drive's artifact as much as a private one's.
  payloadTooLarge,

  /// The codec could not seal the payload — the wallet declined to sign, or
  /// gzip produced nothing.
  sealFailed,
}

/// An artifact that has been built and **not sent**.
///
/// Everything the confirmation modal shows comes from here, and so does
/// everything an upload would need. The two are the same object on purpose:
/// what the user is shown is what would be published, with no second
/// derivation in between that could disagree with it.
class PreparedDriveStateArtifact {
  /// The ArFS entity, tags set and body sealed. Its `txId` is null and stays
  /// null until something uploads it.
  final DriveStateEntity entity;

  final String driveId;

  /// For the confirmation modal. The name is in the payload too, but reading
  /// it back out would mean decrypting what was just sealed.
  final String driveName;

  /// `Entity-Count`: the drive, its folders and its files.
  final int entityCount;

  /// The transaction body's size in bytes — the number an upload is billed on,
  /// after compression, and after encryption when there is any. A public
  /// drive's body is the signed data item itself.
  final int sizeInBytes;

  const PreparedDriveStateArtifact({
    required this.entity,
    required this.driveId,
    required this.driveName,
    required this.entityCount,
    required this.sizeInBytes,
  });

  int get blockStart => entity.blockStart;
  int get blockEnd => entity.blockEnd!;
  int get dataStart => entity.dataStart!;
  int get dataEnd => entity.dataEnd!;

  /// Whether what was sealed is ciphertext. Read off the entity's own `Cipher`
  /// tag rather than carried as a second field, so it can only ever say what
  /// would actually be published.
  bool get isEncrypted => entity.cipher != null;
}

/// A prepared artifact, or a refusal with the sentence explaining it.
class DriveStateCreationResult {
  /// `null` when refused.
  final PreparedDriveStateArtifact? artifact;

  /// `null` when [isPrepared].
  final DriveStateCreationRefusal? refusal;

  /// Why it was refused, in a sentence fit to show the user. A refusal the
  /// user cannot act on is the silent failure this design exists to remove.
  final String reason;

  const DriveStateCreationResult._(this.artifact, this.refusal, this.reason);

  const DriveStateCreationResult.prepared(PreparedDriveStateArtifact artifact)
      : this._(artifact, null, '');

  const DriveStateCreationResult.refused(
    DriveStateCreationRefusal refusal,
    String reason,
  ) : this._(null, refusal, reason);

  bool get isPrepared => artifact != null;
  bool get isRefused => refusal != null;

  @override
  String toString() => isPrepared
      ? 'DriveStateCreationResult(prepared, ${artifact!.sizeInBytes} bytes, '
          '${artifact!.entityCount} entities)'
      : 'DriveStateCreationResult(${refusal!.name}, $reason)';
}

/// Builds a drive state artifact from the local database, and nothing else.
///
/// Public and private drives both. The privacy of the drive decides only
/// whether the signed payload is encrypted afterwards, and that decision is
/// taken here from the drive row — see [DriveStateProtection] for why it is a
/// type and not an argument.
class DriveStateCreationService {
  final DriveDao _driveDao;
  final DriveStateEnvelopeCodec _codec;
  final DriveStateSyncSkipSource _skipSource;
  final String Function() _newArtifactId;

  DriveStateCreationService({
    required DriveDao driveDao,
    required DriveStateSyncSkipSource skipSource,
    DriveStateEnvelopeCodec? codec,
    String Function()? newArtifactId,
  })  : _driveDao = driveDao,
        _skipSource = skipSource,
        _codec = codec ?? DriveStateEnvelopeCodec(),
        _newArtifactId = newArtifactId ?? _uuid;

  static String _uuid() => const Uuid().v4();

  /// Exports [driveId], seals it with [wallet]'s signature, and returns the
  /// entity that would be published.
  ///
  /// [driveKey] is nullable and is *not* how the privacy of the result is
  /// decided. This method reads the drive row and resolves the protection from
  /// the row's own `privacy` column, so a caller cannot ask for an unencrypted
  /// artifact — it hands over whatever key it managed to obtain and is told
  /// what may be built. A private drive with no key is refused; a public drive
  /// with no key is sealed in the clear, which is what a public drive's
  /// artifact is.
  ///
  /// Nothing is sent. The returned entity has no transaction id, and this
  /// class has no way to give it one.
  /// Marks a stage of [prepare], with how long the previous one took.
  ///
  /// The publish path used to log nothing between opening the modal and being
  /// ready, so a preparation that stopped part-way was indistinguishable from
  /// one that was merely slow: no stage, no timing, no reason. That is the
  /// failure §7 exists to prevent, in the one flow §7's vocabulary did not
  /// reach — and it cost an afternoon of guessing from an empty network tab.
  ///
  /// Deliberately `logger.i` rather than `logger.d`: a debug line that is
  /// filtered out by default is not there when somebody needs it, and this is
  /// a handful of lines per user-initiated publish, not a loop.
  void _stage(String driveId, String stage, Stopwatch since) {
    logger.i('[drive-state] $driveId: $stage '
        '(+${since.elapsedMilliseconds}ms)');
    since.reset();
  }

  Future<DriveStateCreationResult> prepare({
    required String driveId,
    required SecretKey? driveKey,
    required Wallet wallet,
  }) async {
    // First, before anything is read and long before anything is sealed. A
    // drive whose completeness cannot be vouched for is not exported at all —
    // there is no partial artifact, no "publish anyway", and no ordering in
    // which the export happens first and the check is consulted afterwards.
    final clock = Stopwatch()..start();
    _stage(driveId, 'preparing an artifact', clock);

    final skipStatus = _skipSource.statusFor(driveId);
    if (!skipStatus.isClean) {
      return DriveStateCreationResult.refused(
        skipStatus.state == DriveStateSyncSkipState.skipped
            ? DriveStateCreationRefusal.syncSkippedEntities
            : DriveStateCreationRefusal.skipStateUnknown,
        skipStatus.reason,
      );
    }

    final drive = await _driveDao.driveById(driveId: driveId).getSingleOrNull();
    if (drive == null) {
      return const DriveStateCreationResult.refused(
        DriveStateCreationRefusal.driveNotFound,
        'This drive is not in your local database.',
      );
    }

    // Resolved from the drive's own row, not from whether the caller happened
    // to have a key. This is the single decision that separates the two
    // chains, and it is taken once, here, from the trustworthy value.
    final resolved = DriveStateProtection.forDrive(
      privacy: drive.privacy,
      driveKey: driveKey,
    );
    if (resolved.isRefused) {
      return DriveStateCreationResult.refused(
        DriveStateCreationRefusal.protectionUnavailable,
        resolved.reason,
      );
    }
    final protection = resolved.protection!;

    if (await wallet.getAddress() != drive.ownerAddress) {
      return const DriveStateCreationResult.refused(
        DriveStateCreationRefusal.notDriveOwner,
        'Only the owner of this drive can publish its state.',
      );
    }

    // `Block-End` is the drive's own watermark and nothing else. It is the
    // coverage claim an importer adopts as its starting point, so it may only
    // be a height this client actually synced to.
    //
    // Checked here to refuse before paying for an export, but *not* used: the
    // number that goes on the wire comes from the export below, which reads
    // the watermark in the same transaction as the rows it carries. This read
    // is a separate one, and a sync batch can land between the two - tagging
    // the earlier value would put a `Block-End` on the transaction that the
    // signed payload contradicts, which every importer rejects. Paid for,
    // permanent, and useless.
    if ((drive.lastBlockHeight ?? 0) <= 0) {
      return const DriveStateCreationResult.refused(
        DriveStateCreationRefusal.noWatermark,
        'This drive has not synced far enough to publish its state. Sync it, '
        'then try again.',
      );
    }

    // The payload is a SQLite database built with ATTACH + INSERT ... SELECT,
    // not a serialisation of rows. Everything downstream — the codec, the
    // entity, the tags, discovery, the uploader — is unchanged by that: they
    // deal in bytes and tags, and the container is not their business.
    if (!artifactSinkSupported) {
      return const DriveStateCreationResult.refused(
        DriveStateCreationRefusal.sealFailed,
        'Publishing a drive state is not available on this platform yet.',
      );
    }

    _stage(driveId, 'checks passed, opening a sink', clock);

    final sink = await createArtifactSink(driveId);
    final sqlite.DriveStateArtifact artifact;
    try {
      artifact = await sqlite.exportDriveState(
        _driveDao.attachedDatabase,
        driveId: driveId,
        sink: sink,
        blockEnd: drive.lastBlockHeight ?? 0,
      );
    } on sqlite.ArtifactExportRefused catch (e) {
      return DriveStateCreationResult.refused(
        e.reason == sqlite.ArtifactExportRefusal.tooLarge
            ? DriveStateCreationRefusal.payloadTooLarge
            : DriveStateCreationRefusal.sealFailed,
        e.detail,
      );
    }
    _stage(
      driveId,
      'exported ${artifact.entityCount} entities, '
      '${artifact.bytes.length} bytes',
      clock,
    );

    final blockEnd = artifact.blockEnd;

    // The same gate again, against the value that will actually be published.
    // Reachable if the drive was reset or detached mid-prepare.
    if (blockEnd <= 0) {
      return const DriveStateCreationResult.refused(
        DriveStateCreationRefusal.noWatermark,
        'This drive has not synced far enough to publish its state. Sync it, '
        'then try again.',
      );
    }

    final plaintext = artifact.bytes;

    // The signature happens inside `seal`, so a wallet that never answers
    // stops between this line and the next.
    _stage(driveId, 'sealing (gzip, sign, encrypt)', clock);

    final sealed = await _codec.seal(
      plaintext: plaintext,
      protection: protection,
      wallet: wallet,
    );

    if (sealed.isRefused) {
      return DriveStateCreationResult.refused(
        sealed.failure == DriveStateEnvelopeFailure.plaintextTooLarge
            ? DriveStateCreationRefusal.payloadTooLarge
            : DriveStateCreationRefusal.sealFailed,
        _sealRefusalMessage(sealed.failure!),
      );
    }

    final envelope = sealed.envelope!;
    _stage(driveId, 'sealed ${envelope.body.lengthInBytes} bytes', clock);

    final entity = DriveStateEntity.fromEnvelope(
      envelope: envelope,
      id: _newArtifactId(),
      driveId: driveId,
      // Both tags come from the payload's own claim, so they cannot
      // contradict it. `Block-Start` is always 0 there, because every
      // artifact is a full copy of the drive as of its `Block-End` and
      // supersedes every earlier one outright (§3.4).
      coverage: DriveStateCoverage(blockStart: 0, blockEnd: blockEnd),
      dataStart: _dataStart(artifact),
      dataEnd: _dataEnd(artifact, blockEnd),
      entityCount: artifact.entityCount,
    );

    _stage(driveId, 'ready to price', clock);

    return DriveStateCreationResult.prepared(
      PreparedDriveStateArtifact(
        entity: entity,
        driveId: driveId,
        driveName: drive.name,
        entityCount: artifact.entityCount,
        sizeInBytes: envelope.body.lengthInBytes,
      ),
    );
  }

  /// `Data-Start` / `Data-End`, derived from the rows the export actually
  /// carries.
  ///
  /// The snapshot entity gets these from the block heights of the transactions
  /// it walked. An artifact has no such heights to read: `file_entries` and
  /// `folder_entries` record dates, not block heights, and the export
  /// deliberately withholds even the drive's own watermark from the payload.
  /// So the honest claim this producer can make is the one its own coverage
  /// supports — the whole searched range — with the emptiness signalled the
  /// way `SnapshotItemToBeCreated` signals it, as -1.
  ///
  /// That keeps the tag doing the job §3.2 gives it: a client can tell an
  /// artifact carries no entities without fetching and decrypting it. An
  /// export with no folders and no files is a drive with nothing in it — not
  /// even a root folder row — which is a drive worth nothing to publish.
  /// `Data-Start` / `Data-End` — the range where data was actually found, as
  /// against the range searched. `-1` for an empty artifact, so a reader can
  /// tell "nothing here" from "starts at block 0" without fetching the body.
  ///
  /// The drive row alone is not data: an artifact carrying only its own drive
  /// and no entities has found nothing worth a reader's bandwidth.
  static int _dataStart(sqlite.DriveStateArtifact a) =>
      _carriesEntities(a) ? 0 : -1;

  static int _dataEnd(sqlite.DriveStateArtifact a, int blockEnd) =>
      _carriesEntities(a) ? blockEnd : -1;

  static bool _carriesEntities(sqlite.DriveStateArtifact a) =>
      a.entityCount > 1;

  static String _sealRefusalMessage(DriveStateEnvelopeFailure failure) {
    switch (failure) {
      case DriveStateEnvelopeFailure.plaintextTooLarge:
        return 'This drive is too large to publish as a single artifact. It '
            'will keep syncing from snapshots as it does today.';
      case DriveStateEnvelopeFailure.plaintextForPrivateDrive:
      case DriveStateEnvelopeFailure.ciphertextForPublicDrive:
        // Unreachable from `seal`, which never produces an envelope that
        // contradicts the protection it was handed - the protection is what
        // chooses the chain. Named rather than left to the default so that a
        // future seal-side use of either value stops here for a decision.
        return 'The artifact could not be prepared for this drive\'s privacy. '
            'Try again.';
      case DriveStateEnvelopeFailure.signingFailed:
        return 'Your wallet did not sign the artifact. Try again.';
      default:
        return 'The artifact could not be prepared. Try again.';
    }
  }
}
