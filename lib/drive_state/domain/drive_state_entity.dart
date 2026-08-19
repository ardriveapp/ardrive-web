import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// An ArFS `drive-state` entity: one drive's exported state, sealed by
/// [DriveStateEnvelopeCodec], described by the tags in proposal 3.2.
///
/// It is a sibling of [SnapshotEntity], not a variant of it. Reusing
/// `Entity-Type: "snapshot"` would make an older client claim this entity's
/// block range from its tags, find no `txSnapshots` in the body, and sync
/// nothing for that range while advancing past it — silent data loss. A
/// distinct entity type is what makes the format additive: clients that
/// predate it never query for it (proposal 3.1).
///
/// The body is already encrypted when it reaches this class. Unlike the other
/// entities, whose JSON is encrypted on the way into a transaction, a drive
/// state artifact is signed before it is compressed and encrypted, so sealing
/// belongs to the codec and this class only carries the result and its tags.
///
/// ## Why there is no `Content-Encoding` tag
///
/// The artifact is gzipped, and it still must not say so.
///
/// `Content-Encoding` describes the transferred representation, and this
/// transaction's data is AES-GCM ciphertext. gzip is two layers inside it —
/// `serialise → gzip → sign → encrypt` — so a reader that acted on the tag
/// would be gunzipping ciphertext.
///
/// Readers do act on it. An AR.IO gateway indexes the tag off both L1
/// transactions and bundled data items and echoes it onto the data response
/// (`ar-io-node`, `src/routes/data/handlers.ts`:
/// `res.header('Content-Encoding', dataAttributes.contentEncoding)`). A
/// browser `fetch` then decodes the body at the network layer, before any of
/// this app's code sees it, and fails: `ERR_CONTENT_DECODING_FAILED`. There is
/// no opt-out in a browser, and `dart:io`'s `autoUncompress` defaults to the
/// same behaviour. Because tags are immutable, an artifact published with this
/// tag would be permanently unfetchable through the ordinary data route — on
/// Flutter Web, unfetchable full stop.
///
/// Nothing else in ArDrive sets the tag: `ContentEncodingTag` arrived with
/// this entity and has no other user. Snapshots, which carry comparable bulk,
/// tag `Content-Type: application/json` and stop there.
///
/// The compression is not a secret worth advertising, either: it is described
/// by `State-Version`, which is the tag a reader actually dispatches on.
class DriveStateEntity extends Entity {
  /// `Drive-State-Id`, this entity's own uuid. Mirrors `Snapshot-Id`.
  String? id;

  /// `Drive-Id`, the drive whose state this is.
  String? driveId;

  /// `State-Version`, as `major.minor` — see [DriveStateFormatVersion].
  ///
  /// The same value the payload declares in its own `version` field, from the
  /// same constant, so a producer cannot tag one version and sign another. An
  /// importer cross-checks the two and refuses an artifact whose tag and
  /// signed payload disagree, exactly as it does for `Block-Start`/`Block-End`
  /// — the tag is chosen by whoever posts the transaction and nobody signs it,
  /// so it is a hint and the payload is the claim.
  DriveStateFormatVersion stateVersion;

  /// `Block-Start`.
  ///
  /// Always 0 when this client publishes: every artifact is a full copy of the
  /// drive as of its [blockEnd] and supersedes every earlier one outright, so
  /// there is no ancestor to locate and no chain to assemble (proposal 3.4).
  /// It is read from the tag rather than assumed, because that is a policy for
  /// v1 and not a limitation of the format.
  ///
  /// **A producer must take this from the payload's signed
  /// `DriveStateCoverage`, not from anywhere else.** An importer rejects an
  /// artifact whose coverage tags disagree with the claim inside the
  /// signature, so a tag invented here is an artifact nobody can use — and
  /// nothing published can be corrected.
  int blockStart;

  /// `Block-End`, the highest block height the export accounted for.
  ///
  /// The signed coverage claim's upper bound; see [blockStart].
  int? blockEnd;

  /// `Data-Start`, the first block in which data was found.
  int? dataStart;

  /// `Data-End`, the last block in which data was found.
  int? dataEnd;

  /// `Entity-Count`, how many entities the payload carries.
  ///
  /// An integrity check, not a statistic: GCM proves the ciphertext arrived
  /// intact, and this proves the body meant what the tags promised
  /// (proposal 3.2).
  int? entityCount;

  /// `Cipher`. Always `AES256-GCM`; see [DriveStateEnvelopeCodec].
  String? cipher;

  /// `Cipher-IV`, base64.
  String? cipherIv;

  /// The sealed body — [DriveStateEnvelope.body].
  Uint8List? data;

  DriveStateEntity({
    this.id,
    this.driveId,
    this.stateVersion = DriveStateFormatVersion.current,
    this.blockStart = 0,
    this.blockEnd,
    this.dataStart,
    this.dataEnd,
    this.entityCount,
    this.cipher,
    this.cipherIv,
    this.data,
  }) : super(ArDriveCrypto());

  /// Builds the entity around a sealed [envelope] and the [coverage] its
  /// payload declares, so that the body, the two cipher tags and the block
  /// range can never disagree with each other.
  ///
  /// The coverage object rather than two integers, because an importer
  /// refuses any artifact whose `Block-Start`/`Block-End` tags do not match
  /// the claim inside the signed payload. Passing the numbers separately
  /// leaves a caller free to read the watermark a second time and tag a
  /// height the payload does not support - a self-rejecting artifact, paid
  /// for and permanent. Taking the claim itself makes that unexpressible.
  factory DriveStateEntity.fromEnvelope({
    required DriveStateEnvelope envelope,
    required String id,
    required String driveId,
    required DriveStateCoverage coverage,
    required int dataStart,
    required int dataEnd,
    required int entityCount,
  }) =>
      DriveStateEntity(
        id: id,
        driveId: driveId,
        blockStart: coverage.blockStart,
        blockEnd: coverage.blockEnd,
        dataStart: dataStart,
        dataEnd: dataEnd,
        entityCount: entityCount,
        cipher: envelope.cipher,
        cipherIv: envelope.cipherIvAsBase64,
        data: envelope.body,
      );

  /// Reads the tags off a transaction found by GraphQL. [data] is the body, if
  /// it has been fetched yet.
  static Future<DriveStateEntity> fromTransaction(
    TransactionCommonMixin transaction,
    Uint8List? data,
  ) async {
    try {
      return DriveStateEntity(
        id: transaction.getTag(EntityTag.driveStateId),
        driveId: transaction.getTag(EntityTag.driveId),
        stateVersion: DriveStateFormatVersion.parse(
            transaction.getTag(EntityTag.stateVersion)!),
        blockStart: int.parse(transaction.getTag(EntityTag.blockStart)!),
        blockEnd: int.parse(transaction.getTag(EntityTag.blockEnd)!),
        dataStart: int.parse(transaction.getTag(EntityTag.dataStart) ?? '-1'),
        dataEnd: int.parse(transaction.getTag(EntityTag.dataEnd) ?? '-1'),
        entityCount: int.parse(transaction.getTag(EntityTag.entityCount)!),
        cipher: transaction.getTag(EntityTag.cipher),
        cipherIv: transaction.getTag(EntityTag.cipherIv),
        data: data,
      )
        ..txId = transaction.id
        ..ownerAddress = transaction.owner.address
        ..createdAt = transaction.getCommitTime();
    } catch (error) {
      logger.e('Error parsing transaction: ${transaction.id}', error);
      throw EntityTransactionParseException(transactionId: transaction.id);
    }
  }

  /// The tags without which a published artifact is unreadable, checked before
  /// any of them is written.
  ///
  /// A real check and not an `assert`, unlike every sibling entity. `assert` is
  /// stripped from release builds, so a null here would not stop a release
  /// client: it would interpolate to the literal `null` and publish
  /// `Block-End: null` — a transaction that is paid for, permanent, and refused
  /// by every reader including the client that wrote it, because
  /// [fromTransaction] parses these tags with `int.parse`. There is no way to
  /// correct a tag after the fact, so the only place this can be caught is
  /// before the transaction exists.
  void _requireTags() {
    final missing = <String>[
      if (id == null) 'Drive-State-Id',
      if (driveId == null) 'Drive-Id',
      if (blockEnd == null) 'Block-End',
      if (dataStart == null) 'Data-Start',
      if (dataEnd == null) 'Data-End',
      if (entityCount == null) 'Entity-Count',
      if (cipher == null) 'Cipher',
      if (cipherIv == null) 'Cipher-IV',
    ];

    if (missing.isNotEmpty) {
      throw StateError(
        'A drive state entity cannot be tagged without ${missing.join(', ')}; '
        'publishing it would spend money on an artifact no reader can use.',
      );
    }
  }

  @override
  void addEntityTagsToTransaction<T extends TransactionBase>(T tx) {
    _requireTags();

    tx
      ..addArFsTag()
      ..addTag(EntityTag.entityType, EntityTypeTag.driveState)
      ..addTag(EntityTag.driveId, driveId!)
      ..addTag(EntityTag.driveStateId, id!)
      ..addTag(EntityTag.stateVersion, '$stateVersion')
      // No `Content-Encoding` tag, deliberately and permanently. The class
      // doc says why; the short version is that a gateway echoes it as an
      // HTTP header and the browser then tries to gunzip ciphertext.
      ..addTag(EntityTag.contentType, ContentType.octetStream)
      ..addTag(EntityTag.blockStart, '$blockStart')
      ..addTag(EntityTag.blockEnd, '$blockEnd')
      ..addTag(EntityTag.dataStart, '$dataStart')
      ..addTag(EntityTag.dataEnd, '$dataEnd')
      ..addTag(EntityTag.entityCount, '$entityCount')
      ..addTag(EntityTag.cipher, cipher!)
      ..addTag(EntityTag.cipherIv, cipherIv!);
  }

  @override
  Future<Transaction> asTransaction({
    SecretKey? key,
  }) async {
    if (key != null) {
      throw UnsupportedError(
        'Drive state entities are sealed by DriveStateEnvelopeCodec, not here.',
      );
    }

    final tx = Transaction.withBlobData(data: data!);
    final packageInfo = await PackageInfo.fromPlatform();

    addEntityTagsToTransaction(tx);
    tx.addApplicationTags(
      version: packageInfo.version,
      unixTime: createdAt,
    );

    return tx;
  }

  @override
  Future<DataItem> asDataItem(SecretKey? key) async {
    if (key != null) {
      throw UnsupportedError(
        'Drive state entities are sealed by DriveStateEnvelopeCodec, not here.',
      );
    }

    final item = DataItem.withBlobData(data: data!);
    final packageInfo = await PackageInfo.fromPlatform();

    addEntityTagsToTransaction(item);
    item.addApplicationTags(
      version: packageInfo.version,
      unixTime: createdAt,
    );

    return item;
  }
}
