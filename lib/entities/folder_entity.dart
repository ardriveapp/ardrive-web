import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:json_annotation/json_annotation.dart';

import 'entities.dart';

part 'folder_entity.g.dart';

@JsonSerializable()
class FolderEntity extends EntityWithCustomMetadata {
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? id;
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? driveId;
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? parentFolderId;

  String? name;
  @JsonKey(includeIfNull: false)
  bool? isHidden;

  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<String> reservedGqlTags = [
    ...EntityWithCustomMetadata.sharedReservedGqlTags,
    EntityTag.folderId,
    EntityTag.parentFolderId,
  ];

  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<String> reservedJsonMetadataKeys = [
    ...EntityWithCustomMetadata.sharedReservedJsonMetadataKeys,
    'isHidden',
  ];

  FolderEntity({
    this.id,
    this.driveId,
    this.parentFolderId,
    this.name,
    this.isHidden,
  }) : super(ArDriveCrypto());

  static Future<FolderEntity> fromTransaction(
    TransactionCommonMixin transaction,
    ArDriveCrypto crypto,
    Uint8List data, [
    SecretKey? driveKey,
  ]) async {
    try {
      Map<String, dynamic>? entityJson;
      if (driveKey == null) {
        entityJson = json.decode(utf8.decode(data));
      } else {
        entityJson = await crypto.decryptEntityJson(
          transaction,
          data,
          driveKey,
        );
      }

      final folder = FolderEntity.fromJson(entityJson!)
        ..id = transaction.getTag(EntityTag.folderId)
        ..driveId = transaction.getTag(EntityTag.driveId)
        ..parentFolderId = transaction.getTag(EntityTag.parentFolderId)
        ..txId = transaction.id
        ..ownerAddress = transaction.owner.address
        ..createdAt = transaction.getCommitTime();

      final tags = transaction.tags
          .map(
            (t) => Tag.fromJson(t.toJson()),
          )
          .toList();
      folder.customGqlTags = EntityWithCustomMetadata.getCustomGqlTags(
        folder,
        tags,
      );

      return folder;
    } catch (_) {
      throw EntityTransactionParseException(transactionId: transaction.id);
    }
  }

  @override
  void addEntityTagsToTransaction<T extends TransactionBase>(T tx) {
    assert(id != null && driveId != null && name != null);

    tx
      ..addArFsTag()
      ..addTag(EntityTag.entityType, EntityTypeTag.folder)
      ..addTag(EntityTag.driveId, driveId!)
      ..addTag(EntityTag.folderId, id!);

    if (parentFolderId != null) {
      tx.addTag(EntityTag.parentFolderId, parentFolderId!);
    }
  }

  factory FolderEntity.fromJson(Map<String, dynamic> json) {
    final entity = _$FolderEntityFromJson(json);
    entity.customJsonMetadata = EntityWithCustomMetadata.getCustomJsonMetadata(
      entity,
      json,
    );
    return entity;
  }
  Map<String, dynamic> toJson() {
    final thisJson = _$FolderEntityToJson(this);
    final custom = customJsonMetadata ?? {};
    final merged = {...thisJson, ...custom};
    return merged;
  }
}
