import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drive/services/services.dart';
import 'package:json_annotation/json_annotation.dart';

import 'entities.dart';

part 'file_entity.g.dart';

DateTime _intToDateTime(int v) =>
    v != null ? DateTime.fromMillisecondsSinceEpoch(v) : null;
int _dateTimeToInt(DateTime v) => v.millisecondsSinceEpoch;

@JsonSerializable()
class FileEntity extends Entity {
  @JsonKey(ignore: true)
  String id;
  @JsonKey(ignore: true)
  String driveId;
  @JsonKey(ignore: true)
  String parentFolderId;

  String name;
  int size;
  @JsonKey(fromJson: _intToDateTime, toJson: _dateTimeToInt)
  DateTime lastModifiedDate;
  String dataTxId;

  FileEntity(
      {this.id,
      this.driveId,
      this.parentFolderId,
      this.name,
      this.size,
      this.lastModifiedDate,
      this.dataTxId});

  static Future<FileEntity> fromTransaction(
    TransactionCommonMixin transaction,
    Uint8List data, [
    SecretKey driveKey,
  ]) async {
    Map<String, dynamic> entityJson;
    if (driveKey == null) {
      entityJson = json.decode(utf8.decode(data));
    } else {
      entityJson = await decryptEntityJson(
        transaction,
        data,
        await deriveFileKey(driveKey, transaction.getTag(EntityTag.fileId)),
      ).catchError(Entity.handleTransactionDecryptionException);
    }

    final commitTime = transaction.getCommitTime();

    return FileEntity.fromJson(entityJson)
      ..id = transaction.getTag(EntityTag.fileId)
      ..driveId = transaction.getTag(EntityTag.driveId)
      ..parentFolderId = transaction.getTag(EntityTag.parentFolderId)
      ..lastModifiedDate ??= commitTime
      ..ownerAddress = transaction.owner.address
      ..commitTime = commitTime;
  }

  @override
  Future<Transaction> asTransaction([SecretKey fileKey]) async {
    assert(id != null &&
        driveId != null &&
        parentFolderId != null &&
        name != null &&
        size != null);

    final tx = fileKey == null
        ? Transaction.withJsonData(data: this)
        : await createEncryptedEntityTransaction(this, fileKey);

    tx
      ..addApplicationTags()
      ..addArFsTag()
      ..addTag(EntityTag.entityType, EntityType.file)
      ..addTag(EntityTag.driveId, driveId)
      ..addTag(EntityTag.parentFolderId, parentFolderId)
      ..addTag(EntityTag.fileId, id);

    return tx;
  }

  factory FileEntity.fromJson(Map<String, dynamic> json) =>
      _$FileEntityFromJson(json);
  Map<String, dynamic> toJson() => _$FileEntityToJson(this);
}
