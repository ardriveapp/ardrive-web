import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:json_annotation/json_annotation.dart';

import 'entities.dart';

part 'file_entity.g.dart';

DateTime? _msToDateTime(int? v) =>
    v != null ? DateTime.fromMillisecondsSinceEpoch(v) : null;
int _dateTimeToMs(DateTime? v) => v!.millisecondsSinceEpoch;

@JsonSerializable()
class FileEntity extends EntityWithCustomMetadata {
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? id;
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? driveId;
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? parentFolderId;

  String? name;
  int? size;
  @JsonKey(fromJson: _msToDateTime, toJson: _dateTimeToMs)
  DateTime? lastModifiedDate;
  String? dataTxId;
  @JsonKey(includeIfNull: false)
  String? licenseTxId;
  String? dataContentType;
  @JsonKey(name: 'pinnedDataOwner', includeIfNull: false)
  String? pinnedDataOwnerAddress;
  @JsonKey(includeIfNull: false)
  bool? isHidden;

  @JsonKey(includeIfNull: false)
  List<String>? assignedNames;

  @JsonKey(includeFromJson: true, includeToJson: true)
  Thumbnail? thumbnail;

  @JsonKey(includeIfNull: false, name: 'fallbackTxId')
  String? fallbackTxId;

  @JsonKey(includeIfNull: false)
  String? originalOwner;

  @JsonKey(includeIfNull: false)
  String? importSource;

  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<String> reservedGqlTags = [
    ...EntityWithCustomMetadata.sharedReservedGqlTags,
    EntityTag.fileId,
    EntityTag.parentFolderId,
  ];

  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<String> reservedJsonMetadataKeys = [
    ...EntityWithCustomMetadata.sharedReservedJsonMetadataKeys,
    'size',
    'lastModifiedDate',
    'dataTxId',
    'licenseTxId',
    'dataContentType',
    'isHidden',
  ];

  FileEntity({
    this.id,
    this.driveId,
    this.parentFolderId,
    this.name,
    this.size,
    this.lastModifiedDate,
    this.dataTxId,
    this.licenseTxId,
    this.dataContentType,
    this.pinnedDataOwnerAddress,
    this.isHidden,
    this.thumbnail,
    this.assignedNames,
    this.fallbackTxId,
    this.originalOwner,
    this.importSource,
  }) : super(ArDriveCrypto());

  FileEntity.withUserProvidedDetails({
    required this.name,
    required this.size,
    required this.lastModifiedDate,
  }) : super(ArDriveCrypto());

  static Future<FileEntity> fromTransaction(
    TransactionCommonMixin transaction,
    Uint8List data, {
    SecretKey? driveKey,
    SecretKey? fileKey,
    required ArDriveCrypto crypto,
  }) async {
    try {
      Map<String, dynamic>? entityJson;
      if (driveKey == null && fileKey == null) {
        entityJson = json.decode(utf8.decode(data));
      } else {
        fileKey ??= await crypto.deriveFileKey(
            driveKey!, transaction.getTag(EntityTag.fileId)!);

        entityJson = await crypto.decryptEntityJson(
          transaction,
          data,
          fileKey,
        );
      }

      final commitTime = transaction.getCommitTime();

      final file = FileEntity.fromJson(entityJson!)
        ..id = transaction.getTag(EntityTag.fileId)
        ..driveId = transaction.getTag(EntityTag.driveId)
        ..parentFolderId = transaction.getTag(EntityTag.parentFolderId)
        ..lastModifiedDate ??= commitTime
        ..txId = transaction.id
        ..ownerAddress = transaction.owner.address
        ..bundledIn = transaction.bundledIn?.id
        ..createdAt = commitTime
        ..originalOwner = transaction.getTag('Original-Owner')
        ..importSource = transaction.getTag('Import-Source');

      final tags = transaction.tags
          .map(
            (t) => Tag.fromJson(t.toJson()),
          )
          .toList();
      file.customGqlTags = EntityWithCustomMetadata.getCustomGqlTags(
        file,
        tags,
      );

      return file;
    } catch (e, s) {
      logger.e('Failed to parse transaction: ${transaction.id}', e, s);
      throw EntityTransactionParseException(transactionId: transaction.id);
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
      ..addTag(EntityTag.entityType, EntityTypeTag.file)
      ..addTag(EntityTag.driveId, driveId!)
      ..addTag(EntityTag.parentFolderId, parentFolderId!)
      ..addTag(EntityTag.fileId, id!);
  }

  factory FileEntity.fromJson(Map<String, dynamic> json) {
    final entity = _$FileEntityFromJson(json);
    entity.customJsonMetadata = EntityWithCustomMetadata.getCustomJsonMetadata(
      entity,
      json,
    );
    return entity;
  }

  Map<String, dynamic> toJson() {
    final thisJson = _$FileEntityToJson(this);
    thisJson['assignedNames'] = assignedNames;
    thisJson['thumbnail'] = thumbnail?.toJson();

    final custom = customJsonMetadata ?? {};
    final merged = {...thisJson, ...custom};
    return merged;
  }
}

class Thumbnail {
  List<Variant> variants;

  Thumbnail({required this.variants});

  factory Thumbnail.fromJson(Map<String, dynamic> json) {
    var variantsJson = json['variants'] as List;
    List<Variant> variantsList =
        variantsJson.map((i) => Variant.fromJson(i)).toList();

    return Thumbnail(
      variants: variantsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'variants': variants.map((variant) => variant.toJson()).toList(),
    };
  }
}

class Variant {
  String name;
  String txId;
  int size;
  int width;
  int height;

  Variant({
    required this.name,
    required this.txId,
    required this.size,
    required this.width,
    required this.height,
  });

  factory Variant.fromJson(Map<String, dynamic> json) {
    return Variant(
      name: json['name'],
      txId: json['txId'],
      size: json['size'],
      width: json['width'],
      height: json['height'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'txId': txId,
      'size': size,
      'width': width,
      'height': height,
    };
  }
}
