import 'dart:convert';

import 'package:arweave/arweave.dart';
import 'package:drive/repositories/arweave/arweave.dart';
import 'package:drive/repositories/entities/entity.dart';
import 'package:json_annotation/json_annotation.dart';

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

  factory DriveEntity.fromTransaction(
    TransactionCommonMixin transaction,
    Map<String, dynamic> entityJson,
  ) =>
      DriveEntity.fromJson(entityJson)
        ..id = transaction.getTag(EntityTag.driveId)
        ..privacy =
            transaction.getTag(EntityTag.drivePrivacy) ?? DrivePrivacy.public
        ..ownerAddress = transaction.owner.address
        ..commitTime = transaction.getCommitTime();

  @override
  Transaction asTransaction() {
    assert(id != null && rootFolderId != null);

    final tx = Transaction.withStringData(data: json.encode(toJson()));

    tx.addApplicationTags();
    tx.addJsonContentTypeTag();
    tx.addTag(EntityTag.entityType, EntityType.drive);
    tx.addTag(EntityTag.driveId, id);

    return tx;
  }

  factory DriveEntity.fromJson(Map<String, dynamic> json) =>
      _$DriveEntityFromJson(json);
  Map<String, dynamic> toJson() => _$DriveEntityToJson(this);
}
