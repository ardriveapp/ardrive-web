import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:json_annotation/json_annotation.dart';

import 'entities.dart';

part 'drive_entity.g.dart';

@JsonSerializable()
class DriveEntity extends Entity {
  @JsonKey(ignore: true)
  String? id;
  @JsonKey(ignore: true)
  String? privacy;
  @JsonKey(ignore: true)
  String? authMode;

  String? name;
  String? rootFolderId;

  DriveEntity(
      {this.id, this.name, this.rootFolderId, this.privacy, this.authMode});

  static Future<DriveEntity> fromTransaction(
    TransactionCommonMixin transaction,
    Uint8List data, [
    SecretKey? driveKey,
  ]) async {
    try {
      final drivePrivacy =
          transaction.getTag(EntityTag.drivePrivacy) ?? DrivePrivacy.public;

      Map<String, dynamic>? entityJson;
      if (drivePrivacy == DrivePrivacy.public) {
        entityJson = json.decode(utf8.decode(data));
      } else if (drivePrivacy == DrivePrivacy.private) {
        entityJson = await decryptEntityJson(transaction, data, driveKey);
      }

      return DriveEntity.fromJson(entityJson!)
        ..id = transaction.getTag(EntityTag.driveId)
        ..privacy = drivePrivacy
        ..authMode = transaction.getTag(EntityTag.driveAuthMode)
        ..txId = transaction.id
        ..ownerAddress = transaction.owner.address
        ..createdAt = transaction.getCommitTime();
    } catch (_) {
      throw EntityTransactionParseException();
    }
  }

  @override
  void addEntityTagsToTransaction<T extends TransactionBase>(T tx) {
    assert(id != null && rootFolderId != null);

    tx
      ..addApplicationTags(unixTime: createdAt)
      ..addArFsTag()
      ..addTag(EntityTag.entityType, EntityType.drive)
      ..addTag(EntityTag.driveId, id!)
      ..addTag(EntityTag.drivePrivacy, privacy!);

    if (privacy == DrivePrivacy.private) {
      tx.addTag(EntityTag.driveAuthMode, authMode!);
    }
  }

  factory DriveEntity.fromJson(Map<String, dynamic> json) =>
      _$DriveEntityFromJson(json);
  Map<String, dynamic> toJson() => _$DriveEntityToJson(this);
}
