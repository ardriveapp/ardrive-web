/// The ArFS entity a drive state artifact is published as: its tags, and the
/// rules a reader applies to them.
library;

import 'package:ardrive/drive_state_sqlite/drive_state_artifact_schema.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive_utils/ardrive_utils.dart';

/// The `Entity-Type` this branch publishes under.
///
/// **Deliberately not `drive-state`.** While the format is being tried out,
/// experiments must be invisible to any client that later implements the real
/// thing — and the strongest way to get that is an entity type nobody queries
/// for, rather than a version field every reader has to remember to check.
/// A client that does not know this type never queries it, never fetches it,
/// and never claims its block range, so an experiment on staging cannot
/// silently become part of a drive's history.
///
/// Renaming this to `drive-state` is the moment the format goes live, and it
/// should happen in its own commit, next to the `1.0` version bump.
const driveStateEntityType = 'drive-state-test';

/// Tags this entity adds beyond the ArFS set already in [EntityTag].
///
/// `Drive-State-Id` mirrors `Snapshot-Id`. `State-Version` mirrors the
/// payload's `meta.version`, and a reader refuses an artifact whose two
/// disagree: the tag is chosen by whoever posts the transaction, the payload
/// is what the owner signed.
///
/// `Entity-Count` is an integrity check rather than a statistic. It proves the
/// body meant what its own header promised, and it is cheap to verify after
/// import.
class DriveStateTag {
  static const driveStateId = 'Drive-State-Id';
  static const stateVersion = 'State-Version';
  static const entityCount = 'Entity-Count';
}

/// The tags an artifact transaction carries.
///
/// **`Content-Encoding` is deliberately absent, and must never be added.** The
/// payload really is gzipped, so declaring it looks correct — but `ar-io-node`
/// indexes that tag from both L1 transactions and bundled data items and
/// echoes it onto the data response. What a gateway serves here is GCM
/// ciphertext, so a browser told it is gzip would try to inflate ciphertext
/// and fail with `ERR_CONTENT_DECODING_FAILED`, with no way for a client to
/// opt out. Tags are immutable, so every artifact published with it would be
/// permanently unfetchable. The compression is instead a property of the
/// format, at a version a reader already knows from `State-Version`.
///
/// No size tag either: `data.size` is already queryable, so a reader can
/// decide not to download an artifact too large for it without spending a
/// byte. And no `Supersedes` pointer — it is derivable from `Block-End`
/// ordering, and a tag that duplicates derivable state is one that can
/// eventually disagree with it.
/// Returned as plain name/value pairs, **not** as `Tag` objects: `Tag` stores
/// its name and value already base64-encoded, so constructing them here would
/// double-encode. The caller applies these with `addTag`, which does the
/// encoding once.
Map<String, String> driveStateTags({
  required String driveId,
  required String driveStateId,
  required int blockStart,
  required int blockEnd,
  required int entityCount,
  required DateTime unixTime,
  String? cipher,
  String? cipherIv,
}) {
  if ((cipher == null) != (cipherIv == null)) {
    throw ArgumentError(
      'cipher and cipherIv must be given together or not at all',
    );
  }
  return {
    EntityTag.arFs: '0.15',
    EntityTag.entityType: driveStateEntityType,
    EntityTag.driveId: driveId,
    DriveStateTag.driveStateId: driveStateId,
    DriveStateTag.stateVersion: artifactFormatVersion,
    EntityTag.contentType: ContentType.octetStream,
    EntityTag.blockStart: '$blockStart',
    EntityTag.blockEnd: '$blockEnd',
    DriveStateTag.entityCount: '$entityCount',
    EntityTag.unixTime: '${unixTime.millisecondsSinceEpoch ~/ 1000}',
    if (cipher != null) EntityTag.cipher: cipher,
    if (cipherIv != null) EntityTag.cipherIv: cipherIv,
  };
}

/// Why a candidate transaction's tags disqualify it, before its body is
/// fetched.
///
/// Checking here is what makes discovery cheap: the tags cost one GraphQL
/// page, the body costs a download. Every value is still a fallback — the
/// caller logs it and syncs normally.
enum DriveStateTagRefusal {
  wrongEntityType,
  wrongDrive,
  unsupportedVersion,
  malformedTags,

  /// A private drive's artifact with no cipher, or a public drive's with one.
  /// Either way it is not a format this reader agreed to, and accepting the
  /// first would normalise the one publication that can never be taken back.
  privacyMismatch,

  /// The artifact covers no more than what is already synced. A no-op, never
  /// a regression.
  rangeAlreadyCovered,

  /// Larger than this client is willing to hold. `data.size` answers this
  /// before any bytes move — see the note on the absent size tag.
  tooLarge,
}

class DriveStateCandidate {
  final String transactionId;
  final String driveId;
  final String driveStateId;
  final String version;
  final int blockStart;
  final int blockEnd;
  final int entityCount;
  final String? cipher;
  final String? cipherIv;
  final int dataSize;

  const DriveStateCandidate({
    required this.transactionId,
    required this.driveId,
    required this.driveStateId,
    required this.version,
    required this.blockStart,
    required this.blockEnd,
    required this.entityCount,
    required this.dataSize,
    this.cipher,
    this.cipherIv,
  });

  bool get isEncrypted => cipher != null;

  /// Reads a candidate out of a transaction's tags. Returns null if the tags
  /// are not this entity at all, or cannot be parsed — both of which mean
  /// "not for us", never "fail the drive".
  static DriveStateCandidate? fromTags(
    Map<String, String> tags, {
    required String transactionId,
    required int dataSize,
  }) {
    if (tags[EntityTag.entityType] != driveStateEntityType) return null;

    final driveId = tags[EntityTag.driveId];
    final driveStateId = tags[DriveStateTag.driveStateId];
    final version = tags[DriveStateTag.stateVersion];
    final blockStart = int.tryParse(tags[EntityTag.blockStart] ?? '');
    final blockEnd = int.tryParse(tags[EntityTag.blockEnd] ?? '');
    final entityCount = int.tryParse(tags[DriveStateTag.entityCount] ?? '');
    if (driveId == null ||
        driveStateId == null ||
        version == null ||
        blockStart == null ||
        blockEnd == null ||
        entityCount == null) {
      return null;
    }

    final cipher = tags[EntityTag.cipher];
    final cipherIv = tags[EntityTag.cipherIv];
    if ((cipher == null) != (cipherIv == null)) return null;

    return DriveStateCandidate(
      transactionId: transactionId,
      driveId: driveId,
      driveStateId: driveStateId,
      version: version,
      blockStart: blockStart,
      blockEnd: blockEnd,
      entityCount: entityCount,
      cipher: cipher,
      cipherIv: cipherIv,
      dataSize: dataSize,
    );
  }

  /// Everything decidable without downloading the body.
  DriveStateTagRefusal? refuseOnTags({
    required String expectedDriveId,
    required bool driveIsPrivate,
    required int syncedToBlock,
    int? maxBytes,
  }) {
    if (driveId != expectedDriveId) return DriveStateTagRefusal.wrongDrive;
    if (!artifactVersionIsReadable(version)) {
      return DriveStateTagRefusal.unsupportedVersion;
    }
    if (blockEnd < blockStart) return DriveStateTagRefusal.malformedTags;
    if (entityCount <= 0) return DriveStateTagRefusal.malformedTags;
    if (driveIsPrivate != isEncrypted) {
      return DriveStateTagRefusal.privacyMismatch;
    }
    if (blockEnd <= syncedToBlock) {
      return DriveStateTagRefusal.rangeAlreadyCovered;
    }
    if (maxBytes != null && dataSize > maxBytes) {
      return DriveStateTagRefusal.tooLarge;
    }
    return null;
  }
}
