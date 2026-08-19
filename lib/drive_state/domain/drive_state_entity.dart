import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
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
class DriveStateEntity extends Entity {
  /// The version of the artifact this client writes, in the `State-Version`
  /// tag. A reader that does not know a version must fall back rather than
  /// guess.
  static const int currentStateVersion = 1;

  /// `Drive-State-Id`, this entity's own uuid. Mirrors `Snapshot-Id`.
  String? id;

  /// `Drive-Id`, the drive whose state this is.
  String? driveId;

  /// `State-Version`.
  int stateVersion;

  /// `Block-Start`.
  ///
  /// Always 0 when this client publishes: every artifact is a full copy of the
  /// drive as of its [blockEnd] and supersedes every earlier one outright, so
  /// there is no ancestor to locate and no chain to assemble (proposal 3.4).
  /// It is read from the tag rather than assumed, because that is a policy for
  /// v1 and not a limitation of the format.
  int blockStart;

  /// `Block-End`, the highest block height the export accounted for.
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
    this.stateVersion = currentStateVersion,
    this.blockStart = 0,
    this.blockEnd,
    this.dataStart,
    this.dataEnd,
    this.entityCount,
    this.cipher,
    this.cipherIv,
    this.data,
  }) : super(ArDriveCrypto());

  /// Builds the entity around a sealed [envelope], so that the body and the
  /// two cipher tags can never disagree with each other.
  factory DriveStateEntity.fromEnvelope({
    required DriveStateEnvelope envelope,
    required String id,
    required String driveId,
    required int blockEnd,
    required int dataStart,
    required int dataEnd,
    required int entityCount,
  }) =>
      DriveStateEntity(
        id: id,
        driveId: driveId,
        blockEnd: blockEnd,
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
        stateVersion: int.parse(transaction.getTag(EntityTag.stateVersion)!),
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

  @override
  void addEntityTagsToTransaction<T extends TransactionBase>(T tx) {
    assert(id != null &&
        driveId != null &&
        blockEnd != null &&
        dataStart != null &&
        dataEnd != null &&
        entityCount != null &&
        cipher != null &&
        cipherIv != null);

    tx
      ..addArFsTag()
      ..addTag(EntityTag.entityType, EntityTypeTag.driveState)
      ..addTag(EntityTag.driveId, driveId!)
      ..addTag(EntityTag.driveStateId, id!)
      ..addTag(EntityTag.stateVersion, '$stateVersion')
      ..addTag(EntityTag.contentType, ContentType.octetStream)
      ..addTag(EntityTag.contentEncoding, ContentEncodingTag.gzip)
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
