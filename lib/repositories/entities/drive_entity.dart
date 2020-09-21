import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:pointycastle/export.dart';

import '../graphql/graphql.dart';
import 'entities.dart';

part 'drive_entity.g.dart';

@JsonSerializable()
class DriveEntity extends Entity {
  @JsonKey(ignore: true)
  String id;
  @JsonKey(ignore: true)
  String privacy;
  @JsonKey(ignore: true)
  String authMode;

  String rootFolderId;

  DriveEntity({this.id, this.rootFolderId, this.privacy, this.authMode});

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
      ..authMode = transaction.getTag(EntityTag.driveAuthMode)
      ..ownerAddress = transaction.owner.address
      ..commitTime = transaction.getCommitTime();
  }

  @override
  Future<Transaction> asTransaction([KeyParameter driveKey]) async {
    assert(id != null && rootFolderId != null);

    final tx = driveKey == null
        ? Transaction.withJsonData(data: this)
        : await createEncryptedEntityTransaction(this, driveKey);

    tx
      ..addApplicationTags()
      ..addTag(EntityTag.entityType, EntityType.drive)
      ..addTag(EntityTag.driveId, id);

    if (privacy == DrivePrivacy.private) {
      tx
        ..addTag(EntityTag.drivePrivacy, privacy)
        ..addTag(EntityTag.driveAuthMode, authMode);
    }

    return tx;
  }

  factory DriveEntity.fromJson(Map<String, dynamic> json) =>
      _$DriveEntityFromJson(json);
  Map<String, dynamic> toJson() => _$DriveEntityToJson(this);
}
