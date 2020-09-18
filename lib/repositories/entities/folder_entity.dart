import 'dart:convert';

import 'package:arweave/arweave.dart';
import 'package:drive/repositories/arweave/arweave.dart';
import 'package:drive/repositories/entities/entity.dart';
import 'package:json_annotation/json_annotation.dart';

import '../arweave/utils.dart';
import 'constants.dart';

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

  factory FolderEntity.fromTransaction(
    TransactionCommonMixin transaction,
    Map<String, dynamic> entityJson,
  ) =>
      FolderEntity.fromJson(entityJson)
        ..id = transaction.getTag(EntityTag.folderId)
        ..driveId = transaction.getTag(EntityTag.driveId)
        ..parentFolderId = transaction.getTag(EntityTag.parentFolderId)
        ..ownerAddress = transaction.owner.address
        ..commitTime = transaction.getCommitTime();

  @override
  Transaction asTransaction() {
    assert(id != null && driveId != null && name != null);

    final tx = Transaction.withStringData(data: json.encode(toJson()));

    tx.addApplicationTags();
    tx.addJsonContentTypeTag();
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
