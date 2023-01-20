import 'dart:typed_data';

import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'entities.dart';

part 'snapshot_entity.g.dart';

@JsonSerializable()
class SnapshotEntity extends Entity {
  @JsonKey(ignore: true)
  String? id;
  @JsonKey(ignore: true)
  String? driveId;
  @JsonKey(ignore: true)
  int? blockStart;
  @JsonKey(ignore: true)
  int? blockEnd;
  @JsonKey(ignore: true)
  int? dataStart;
  @JsonKey(ignore: true)
  int? dataEnd;

  @JsonKey(ignore: true)
  Uint8List? data;

  SnapshotEntity({
    this.id,
    this.driveId,
    this.blockStart,
    this.blockEnd,
    this.dataStart,
    this.dataEnd,
    this.data,
  });

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
        dataStart: int.parse(transaction.getTag(EntityTag.dataStart)!),
        dataEnd: int.parse(transaction.getTag(EntityTag.dataEnd)!),
        data: data,
      )
        ..txId = transaction.id
        ..ownerAddress = transaction.owner.address
        ..createdAt = transaction.getCommitTime();
    } catch (_) {
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
      ..addTag(EntityTag.entityType, EntityType.snapshot)
      ..addTag(EntityTag.driveId, driveId!)
      ..addTag(EntityTag.snapshotId, id!)
      ..addTag(EntityTag.blockStart, '$blockStart')
      ..addTag(EntityTag.blockEnd, '$blockEnd')
      ..addTag(EntityTag.dataStart, '$dataStart')
      ..addTag(EntityTag.dataEnd, '$dataEnd');
  }

  Future<DataItem> asPreparedDataItem({
    required ArweaveAddress owner,
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

    final tx = Transaction.withJsonData(data: data!);
    final packageInfo = await PackageInfo.fromPlatform();

    addEntityTagsToTransaction(tx);

    tx.addApplicationTags(
      version: packageInfo.version,
      unixTime: createdAt,
    );
    return tx;
  }
}
