import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:json_annotation/json_annotation.dart';

import 'entities.dart';

part 'drive_entity.g.dart';

@JsonSerializable()
class DriveEntity extends EntityWithCustomMetadata {
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? id;
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? privacy;
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? authMode;

  String? name;
  String? rootFolderId;

  bool? isHidden;

  @JsonKey(includeFromJson: false, includeToJson: false)
  DriveSignatureType? signatureType;

  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<String> reservedGqlTags = [
    ...EntityWithCustomMetadata.sharedReservedGqlTags,
    EntityTag.drivePrivacy,
    EntityTag.driveAuthMode,
    EntityTag.signatureType
  ];

  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<String> reservedJsonMetadataKeys = [
    ...EntityWithCustomMetadata.sharedReservedJsonMetadataKeys,
    'rootFolderId',
  ];

  DriveEntity(
      {this.id,
      this.name,
      this.rootFolderId,
      this.privacy,
      this.authMode,
      this.isHidden,
      this.signatureType})
      : super(ArDriveCrypto());

  static Future<DriveEntity> fromTransaction(
    TransactionCommonMixin transaction,
    ArDriveCrypto crypto,
    Uint8List data, [
    SecretKey? driveKey,
  ]) async {
    try {
      final drivePrivacy =
          transaction.getTag(EntityTag.drivePrivacy) ?? DrivePrivacyTag.public;

      Map<String, dynamic>? entityJson;
      if (drivePrivacy == DrivePrivacyTag.public) {
        entityJson = json.decode(utf8.decode(data));
      } else if (drivePrivacy == DrivePrivacyTag.private) {
        entityJson =
            await crypto.decryptEntityJson(transaction, data, driveKey!);
      }

      final drive = DriveEntity.fromJson(entityJson!)
        ..id = transaction.getTag(EntityTag.driveId)
        ..privacy = drivePrivacy
        ..authMode = transaction.getTag(EntityTag.driveAuthMode)
        ..txId = transaction.id
        ..ownerAddress = transaction.owner.address
        ..bundledIn = transaction.bundledIn?.id
        ..createdAt = transaction.getCommitTime()
        ..signatureType = DriveSignatureType.fromString(
            transaction.getTag(EntityTag.signatureType) ?? '1');

      final tags = transaction.tags
          .map(
            (t) => Tag.fromJson(t.toJson()),
          )
          .toList();
      drive.customGqlTags = EntityWithCustomMetadata.getCustomGqlTags(
        drive,
        tags,
      );

      return drive;
    } catch (_) {
      throw EntityTransactionParseException(transactionId: transaction.id);
    }
  }

  @override
  void addEntityTagsToTransaction<T extends TransactionBase>(T tx) {
    assert(id != null && rootFolderId != null && privacy != null);

    tx
      ..addArFsTag()
      ..addTag(EntityTag.entityType, EntityTypeTag.drive)
      ..addTag(EntityTag.driveId, id!)
      ..addTag(EntityTag.drivePrivacy, privacy!);

    if (privacy == DrivePrivacyTag.private) {
      tx.addTag(EntityTag.driveAuthMode, authMode!);
      tx.addTag(EntityTag.signatureType, signatureType?.value ?? '1');
    }
  }

  factory DriveEntity.fromJson(Map<String, dynamic> json) {
    final entity = _$DriveEntityFromJson(json);
    entity.customJsonMetadata = EntityWithCustomMetadata.getCustomJsonMetadata(
      entity,
      json,
    );
    return entity;
  }
  Map<String, dynamic> toJson() {
    final thisJson = _$DriveEntityToJson(this);
    final custom = customJsonMetadata ?? {};
    final merged = {...thisJson, ...custom};
    return merged;
  }
}
