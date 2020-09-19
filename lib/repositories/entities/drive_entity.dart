import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:drive/repositories/arweave/arweave.dart';
import 'package:drive/repositories/entities/entity.dart';
import 'package:drive/services/crypto/crypto.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:pointycastle/export.dart';

import '../arweave/utils.dart';
import 'constants.dart';

part 'drive_entity.g.dart';

@JsonSerializable()
class DriveEntity extends Entity {
  @JsonKey(ignore: true)
  String id;
  @JsonKey(ignore: true)
  String privacy;

  String rootFolderId;

  DriveEntity({this.id, this.rootFolderId});

  static Future<DriveEntity> fromTransaction(
    TransactionCommonMixin transaction,
    Uint8List data, [
    KeyParameter driveKey,
  ]) async {
    final entityJson = driveKey == null
        ? json.decode(utf8.decode(data))
        : await decryptDriveEntityJson(transaction, data, driveKey);

    return DriveEntity.fromJson(entityJson)
      ..id = transaction.getTag(EntityTag.driveId)
      ..privacy =
          transaction.getTag(EntityTag.drivePrivacy) ?? DrivePrivacy.public
      ..ownerAddress = transaction.owner.address
      ..commitTime = transaction.getCommitTime();
  }

  @override
  Future<Transaction> asTransaction([KeyParameter driveKey]) async {
    assert(id != null && rootFolderId != null);

    final tx = driveKey == null
        ? Transaction.withJsonData(data: this)
        : await createEncryptedEntityTransaction(this, driveKey);

    tx.addApplicationTags();
    tx.addTag(EntityTag.entityType, EntityType.drive);
    tx.addTag(EntityTag.driveId, id);

    return tx;
  }

  factory DriveEntity.fromJson(Map<String, dynamic> json) =>
      _$DriveEntityFromJson(json);
  Map<String, dynamic> toJson() => _$DriveEntityToJson(this);
}
