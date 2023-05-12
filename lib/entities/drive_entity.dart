import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/custom_metadata.dart';
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
  @JsonKey(ignore: true)
  String? customJsonMetaData;
  @JsonKey(ignore: true)
  Uint8List? metadata;

  String? name;
  String? rootFolderId;

  DriveEntity({
    String? id,
    this.name,
    this.rootFolderId,
    this.customJsonMetaData,
    this.privacy,
    this.authMode,
  }) : super(ArDriveCrypto());

  static Future<DriveEntity> fromTransaction(
    TransactionCommonMixin transaction,
    ArDriveCrypto crypto,
    Uint8List data, [
    SecretKey? driveKey,
  ]) async {
    try {
      final drivePrivacy =
          transaction.getTag(EntityTag.drivePrivacy) ?? DrivePrivacy.public;
      Map<String, dynamic>? entityJson =
          await parseJsonMetadata(data, transaction, driveKey, crypto);
      // Uint8List entityJsonAsBlob =
      //     Uint8List.fromList(utf8.encode(json.encode(entityJson)));

      return DriveEntity.fromJson(entityJson)
        ..id = transaction.getTag(EntityTag.driveId)
        ..privacy = drivePrivacy
        ..authMode = transaction.getTag(EntityTag.driveAuthMode)
        ..txId = transaction.id
        ..ownerAddress = transaction.owner.address
        ..bundledIn = transaction.bundledIn?.id
        ..customJsonMetaData = extractCustomMetadataForEntityType(
          entityJson,
          entityType: EntityType.drive,
        )
        ..metadata = data
        ..createdAt = transaction.getCommitTime();
    } catch (_) {
      throw EntityTransactionParseException(transactionId: transaction.id);
    }
  }

  static Future<Map<String, dynamic>> parseJsonMetadata(
    Uint8List data,
    TransactionCommonMixin transaction,
    SecretKey? driveKey,
    ArDriveCrypto crypto,
  ) async {
    final drivePrivacy =
        transaction.getTag(EntityTag.drivePrivacy) ?? DrivePrivacy.public;

    Map<String, dynamic>? entityJson;
    if (drivePrivacy == DrivePrivacy.public) {
      entityJson = json.decode(utf8.decode(data));
    } else if (drivePrivacy == DrivePrivacy.private) {
      entityJson = await crypto.decryptEntityJson(transaction, data, driveKey!);
    }

    return entityJson!;
  }

  @override
  void addEntityTagsToTransaction<T extends TransactionBase>(T tx) {
    assert(id != null && rootFolderId != null);

    tx
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
