import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:pointycastle/export.dart';

import '../graphql/graphql.dart';
import 'entities.dart';

part 'folder_entity.g.dart';

@JsonSerializable()
class FolderEntity extends Entity {
  @JsonKey(ignore: true)
  String id;
  @JsonKey(ignore: true)
  String driveId;
  @JsonKey(ignore: true)
  String parentFolderId;

  String name;

  FolderEntity({this.id, this.driveId, this.parentFolderId, this.name});

  static Future<FolderEntity> fromTransaction(
    TransactionCommonMixin transaction,
    Uint8List data, [
    KeyParameter driveKey,
  ]) async {
    final entityJson = driveKey == null
        ? json.decode(utf8.decode(data))
        : await decryptFolderEntityJson(transaction, data, driveKey);

    return FolderEntity.fromJson(entityJson)
      ..id = transaction.getTag(EntityTag.folderId)
      ..driveId = transaction.getTag(EntityTag.driveId)
      ..parentFolderId = transaction.getTag(EntityTag.parentFolderId)
      ..ownerAddress = transaction.owner.address
      ..commitTime = transaction.getCommitTime();
  }

  @override
  Future<Transaction> asTransaction([KeyParameter driveKey]) async {
    assert(id != null && driveId != null && name != null);

    final tx = driveKey == null
        ? Transaction.withJsonData(data: this)
        : await createEncryptedEntityTransaction(this, driveKey);

    tx.addApplicationTags();
    tx.addTag(EntityTag.entityType, EntityType.folder);
    tx.addTag(EntityTag.driveId, driveId);
    tx.addTag(EntityTag.folderId, id);

    if (parentFolderId != null) {
      tx.addTag(EntityTag.parentFolderId, parentFolderId);
    }

    return tx;
  }

  factory FolderEntity.fromJson(Map<String, dynamic> json) =>
      _$FolderEntityFromJson(json);
  Map<String, dynamic> toJson() => _$FolderEntityToJson(this);
}
