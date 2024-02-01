import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'entities.dart';

part 'snapshot_entity.g.dart';

@JsonSerializable()
class SnapshotEntity extends Entity {
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? id;
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? driveId;
  @JsonKey(includeFromJson: false, includeToJson: false)
  int? blockStart;
  @JsonKey(includeFromJson: false, includeToJson: false)
  int? blockEnd;
  @JsonKey(includeFromJson: false, includeToJson: false)
  int? dataStart;
  @JsonKey(includeFromJson: false, includeToJson: false)
  int? dataEnd;

  @JsonKey(includeFromJson: false, includeToJson: false)
  Uint8List? data;

  SnapshotEntity({
    this.id,
    this.driveId,
    this.blockStart,
    this.blockEnd,
    this.dataStart,
    this.dataEnd,
    this.data,
  }) : super(ArDriveCrypto());

  static Future<SnapshotEntity> fromTransaction(
    TransactionCommonMixin transaction,
    Uint8List? data,
  ) async {
    try {
      return SnapshotEntity(
        id: transaction.getTag(EntityTag.snapshotId),
        driveId: transaction.getTag(EntityTag.driveId),
        blockStart: int.parse(transaction.getTag(EntityTag.blockStart)!),
        blockEnd: int.parse(transaction.getTag(EntityTag.blockEnd)!),
        dataStart: int.parse(transaction.getTag(EntityTag.dataStart) ?? '-1'),
        dataEnd: int.parse(transaction.getTag(EntityTag.dataEnd) ?? '-1'),
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
        blockStart != null &&
        blockEnd != null &&
        dataStart != null &&
        dataEnd != null);

    tx
      ..addArFsTag()
      ..addTag(EntityTag.entityType, EntityTypeTag.snapshot)
      ..addTag(EntityTag.driveId, driveId!)
      ..addTag(EntityTag.snapshotId, id!)
      ..addTag(EntityTag.blockStart, '$blockStart')
      ..addTag(EntityTag.blockEnd, '$blockEnd')
      ..addTag(EntityTag.dataStart, '$dataStart')
      ..addTag(EntityTag.dataEnd, '$dataEnd');
  }

  Future<DataItem> asPreparedDataItem({
    required ArweaveAddressString owner,
  }) async {
    final dataItem = DataItem()
      ..setOwner(owner)
      ..addApplicationTags(
        version: (await PackageInfo.fromPlatform()).version,
      )
      ..addTag(EntityTag.contentType, ContentType.json);

    return dataItem;
  }

  @override
  Future<Transaction> asTransaction({
    SecretKey? key,
  }) async {
    if (key != null) {
      throw UnsupportedError('Snapshot entities are not encrypted.');
    }

    final tx = Transaction.withBlobData(data: data!);
    final packageInfo = await PackageInfo.fromPlatform();

    tx.addTag(EntityTag.contentType, ContentType.json);
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
      throw UnsupportedError('Snapshot entities are not encrypted.');
    }

    final item = DataItem.withBlobData(data: data!);
    final packageInfo = await PackageInfo.fromPlatform();

    item.addTag(EntityTag.contentType, ContentType.json);
    addEntityTagsToTransaction(item);
    item.addApplicationTags(
      version: packageInfo.version,
    );

    return item;
  }
}
