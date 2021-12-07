import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:json_annotation/json_annotation.dart';

import 'entities.dart';

part 'file_entity.g.dart';

DateTime? _msToDateTime(int? v) =>
    v != null ? DateTime.fromMillisecondsSinceEpoch(v) : null;
int _dateTimeToMs(DateTime? v) => v!.millisecondsSinceEpoch;

@JsonSerializable()
class FileEntity extends Entity {
  @JsonKey(ignore: true)
  String? id;
  @JsonKey(ignore: true)
  String? driveId;
  @JsonKey(ignore: true)
  String? parentFolderId;

  String? name;
  int? size;
  @JsonKey(fromJson: _msToDateTime, toJson: _dateTimeToMs)
  DateTime? lastModifiedDate;

  String? dataTxId;
  String? dataContentType;

  FileEntity({
    this.id,
    this.driveId,
    this.parentFolderId,
    this.name,
    this.size,
    this.lastModifiedDate,
    this.dataTxId,
    this.dataContentType,
  });

  FileEntity.withUserProvidedDetails(
      {required this.name, required this.size, required this.lastModifiedDate});

  static Future<FileEntity> fromTransaction(
    TransactionCommonMixin transaction,
    Uint8List data, {
    SecretKey? driveKey,
    SecretKey? fileKey,
  }) async {
    try {
      Map<String, dynamic>? entityJson;
      if (driveKey == null && fileKey == null) {
        entityJson = json.decode(utf8.decode(data));
      } else {
        fileKey ??= await deriveFileKey(
            driveKey!, transaction.getTag(EntityTag.fileId)!);

        entityJson = await decryptEntityJson(
          transaction,
          data,
          fileKey,
        );
      }

      final commitTime = transaction.getCommitTime();

      return FileEntity.fromJson(entityJson!)
        ..id = transaction.getTag(EntityTag.fileId)
        ..driveId = transaction.getTag(EntityTag.driveId)
        ..parentFolderId = transaction.getTag(EntityTag.parentFolderId)
        ..lastModifiedDate ??= commitTime
        ..txId = transaction.id
        ..ownerAddress = transaction.owner.address
        ..createdAt = commitTime;
    } catch (_) {
      throw EntityTransactionParseException();
    }
  }

  @override
  void addEntityTagsToTransaction<T extends TransactionBase>(T tx) {
    assert(id != null &&
        driveId != null &&
        parentFolderId != null &&
        name != null &&
        size != null);

    tx
      ..addArFsTag()
      ..addTag(EntityTag.entityType, EntityType.file)
      ..addTag(EntityTag.driveId, driveId!)
      ..addTag(EntityTag.parentFolderId, parentFolderId!)
      ..addTag(EntityTag.fileId, id!);
  }

  factory FileEntity.fromJson(Map<String, dynamic> json) =>
      _$FileEntityFromJson(json);
  Map<String, dynamic> toJson() => _$FileEntityToJson(this);
}
