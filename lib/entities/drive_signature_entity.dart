import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:json_annotation/json_annotation.dart';

import 'entities.dart';

part 'drive_signature_entity.g.dart';

@JsonSerializable()
class DriveSignatureEntity extends EntityWithCustomMetadata {
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? id;
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? driveId;
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? signatureFormat;
  @JsonKey(includeFromJson: false, includeToJson: false)
  Uint8List? data;

  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<String> reservedGqlTags = [
    ...EntityWithCustomMetadata.sharedReservedGqlTags,
    EntityTag.signatureFormat,
  ];

  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<String> reservedJsonMetadataKeys = [
    ...EntityWithCustomMetadata.sharedReservedJsonMetadataKeys,
  ];

  DriveSignatureEntity({
    this.id,
    this.driveId,
    this.signatureFormat,
  }) : super(ArDriveCrypto());

  static Future<DriveSignatureEntity> fromTransaction(
    TransactionCommonMixin transaction,
    ArDriveCrypto crypto,
    Uint8List data, [
    SecretKey? driveKey,
  ]) async {
    try {
      final entityJson = json.decode(utf8.decode(data));

      final driveSignature = DriveSignatureEntity.fromJson(entityJson!)
        ..id = transaction.getTag(EntityTag.driveId)
        ..txId = transaction.id
        ..ownerAddress = transaction.owner.address
        ..bundledIn = transaction.bundledIn?.id
        ..createdAt = transaction.getCommitTime()
        ..data = data;

      final tags = transaction.tags
          .map(
            (t) => Tag.fromJson(t.toJson()),
          )
          .toList();
      driveSignature.customGqlTags = EntityWithCustomMetadata.getCustomGqlTags(
        driveSignature,
        tags,
      );

      return driveSignature;
    } catch (_) {
      throw EntityTransactionParseException(transactionId: transaction.id);
    }
  }

  @override
  void addEntityTagsToTransaction<T extends TransactionBase>(T tx) {
    assert(id != null && driveId != null);

    tx
      ..addArFsTag()
      ..addTag(EntityTag.entityType, EntityTypeTag.driveSignature)
      ..addTag(EntityTag.driveId, driveId!)
      ..addTag(EntityTag.signatureFormat, signatureFormat!);
  }

  factory DriveSignatureEntity.fromJson(Map<String, dynamic> json) {
    final entity = _$DriveSignatureEntityFromJson(json);
    entity.customJsonMetadata = EntityWithCustomMetadata.getCustomJsonMetadata(
      entity,
      json,
    );
    return entity;
  }
  Map<String, dynamic> toJson() {
    final thisJson = _$DriveSignatureEntityToJson(this);
    final custom = customJsonMetadata ?? {};
    final merged = {...thisJson, ...custom};
    return merged;
  }
}
