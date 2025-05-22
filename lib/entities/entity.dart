import 'dart:convert';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive_logger/ardrive_logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:package_info_plus/package_info_plus.dart';

mixin TransactionPropertiesMixin {
  /// The id of the transaction that represents this entity.
  @JsonKey(includeFromJson: false, includeToJson: false)
  late String txId;

  /// The address of the owner of this entity.
  @JsonKey(includeFromJson: false, includeToJson: false)
  late String ownerAddress;

  /// The bundle this entity is a part of.
  @JsonKey(includeFromJson: false, includeToJson: false)
  String? bundledIn;
}

abstract class Entity with TransactionPropertiesMixin {
  final ArDriveCrypto _crypto;

  /// The time this entity was created at ie. its `Unix-Time`.
  @JsonKey(includeFromJson: false, includeToJson: false)
  DateTime createdAt = DateTime.now();

  Entity(this._crypto);

  /// Returns a [Transaction] with the entity's data along with the appropriate tags.
  ///
  /// If a key is provided, the transaction data is encrypted.
  Future<Transaction> asTransaction({
    SecretKey? key,
  }) async {
    final tx = key == null
        ? Transaction.withJsonData(data: this)
        : await _crypto.createEncryptedEntityTransaction(this, key);
    final packageInfo = await PackageInfo.fromPlatform();

    addEntityTagsToTransaction(tx);
    tx.addApplicationTags(
      version: packageInfo.version,
      unixTime: createdAt,
    );

    return tx;
  }

  /// Returns a [DataItem] with the entity's data along with the appropriate tags.
  ///
  /// The `owner` on this [DataItem] will be unset.
  ///
  /// If a key is provided, the data item data is encrypted.
  Future<DataItem> asDataItem(SecretKey? key) async {
    final item = key == null
        ? DataItem.withJsonData(data: this)
        : await _crypto.createEncryptedEntityDataItem(this, key);
    final packageInfo = await PackageInfo.fromPlatform();

    addEntityTagsToTransaction(item);
    item.addApplicationTags(
      version: packageInfo.version,
    );

    return item;
  }

  @protected
  void addEntityTagsToTransaction<T extends TransactionBase>(T tx);
}

abstract class EntityWithCustomMetadata extends Entity {
  // The custom JSON Metadata sub-JSON.
  /// These are the keys in the JSON Metadata, excluding the reserved ones.
  @JsonKey(includeFromJson: false, includeToJson: false)
  Map<String, dynamic>? customJsonMetadata = {};

  // The reserved JSON Metadata keys.
  @JsonKey(includeFromJson: false, includeToJson: false)
  abstract final List<String> reservedJsonMetadataKeys;

  static List<String> sharedReservedJsonMetadataKeys = [
    // As of ArFS v0.12, all entities except for SNAPSHOT does have a name.
    'name'
  ];

  // The custom GQL Tags.
  /// These are the keys in the GQL Tags, excluding the reserved ones.
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<Tag>? customGqlTags = [];

  // The reserved GQL Tags.
  @JsonKey(includeFromJson: false, includeToJson: false)
  abstract final List<String> reservedGqlTags;

  String? get customJsonMetadataAsString {
    if (customJsonMetadata == null) {
      return null;
    }

    return jsonEncode(customJsonMetadata);
  }

  String? get customGqlTagsAsString {
    if (customGqlTags == null) {
      return null;
    }

    return jsonEncode(customGqlTags);
  }

  static List<String> sharedReservedGqlTags = [
    EntityTag.arFs,
    EntityTag.driveId,
    EntityTag.entityType,
    EntityTag.contentType,
    EntityTag.unixTime,
    EntityTag.cipher,
    EntityTag.cipherIv,
    EntityTag.appName,
    EntityTag.appVersion,
    EntityTag.appPlatform,
    EntityTag.input,
    EntityTag.contract,
    'Bundle-Format',
    'Bundle-Version',
  ];

  EntityWithCustomMetadata(super.crypto);

  @override
  Future<Transaction> asTransaction({
    SecretKey? key,
  }) async {
    final tx = await super.asTransaction(key: key);
    _addCustomGqlTagsToTransaction(tx);
    return tx;
  }

  void _addCustomGqlTagsToTransaction(Transaction tx) {
    if (customGqlTags != null) {
      for (final tag in customGqlTags!) {
        tx.addTag(tag.name, tag.value);
      }
    }
  }

  @override
  Future<DataItem> asDataItem(SecretKey? key) async {
    final item = await super.asDataItem(key);
    _addCustomGqlTagsToDataItem(item);
    return item;
  }

  void _addCustomGqlTagsToDataItem(DataItem item) {
    if (customGqlTags != null) {
      for (final tag in customGqlTags!) {
        item.addTag(tag.name, tag.value);
      }
    }
  }

  static Map<String, dynamic> getCustomJsonMetadata(
    EntityWithCustomMetadata entity,
    Map<String, dynamic> jsonMetadata,
  ) {
    final customJsonMetadata = <String, dynamic>{};
    for (final key in jsonMetadata.keys) {
      if (!entity.reservedJsonMetadataKeys.contains(key)) {
        customJsonMetadata[key] = jsonMetadata[key];
      }
    }
    return customJsonMetadata;
  }

  static List<Tag> getCustomGqlTags(
    EntityWithCustomMetadata entity,
    List<Tag> gqlTags,
  ) {
    final customGqlTags = <Tag>[];
    for (final tag in gqlTags) {
      if (!entity.reservedGqlTags.contains(tag.name)) {
        customGqlTags.add(tag);
      }
    }
    return customGqlTags;
  }
}

class EntityTransactionParseException implements UntrackedException {
  final String transactionId;

  EntityTransactionParseException({required this.transactionId});
}

class EntityTransactionDataNetworkException implements Exception {
  final String transactionId;
  final int statusCode;
  final String? reasonPhrase;
  EntityTransactionDataNetworkException({
    required this.transactionId,
    required this.statusCode,
    required this.reasonPhrase,
  });
}

extension TransactionUtils on TransactionBase {
  /// Tags this transaction with the app name, version, and the specified unix time.
  /// https://ardrive.atlassian.net/wiki/spaces/ENGINEERIN/pages/277544961/Data+Model
  void addApplicationTags({
    required String version,
    DateTime? unixTime,
    bool isWeb = kIsWeb,
  }) {
    final String platform = AppPlatform.getPlatform().name;
    addTag(EntityTag.appName, 'ArDrive-App');
    addTag(
      EntityTag.appPlatform,
      platform,
    );
    addTag(EntityTag.appVersion, version);
    addTag(
        EntityTag.unixTime,
        ((unixTime ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000)
            .toString());
  }

  /// Tags this transaction with the ArFS version currently in use.
  void addArFsTag() {
    addTag(EntityTag.arFs, '0.15');
  }

  void addBundleTags() {
    addTag('Bundle-Format', 'binary');
    addTag('Bundle-Version', '2.0.0');
  }

  void addUTags() {
    addTag(EntityTag.appName, 'SmartWeaveAction');
    addTag(EntityTag.appVersion, '0.3.0');
    addTag(EntityTag.input, '{"function":"mint"}');
    addTag(EntityTag.contract, 'KTzTXT_ANmF84fWEKHzWURD1LWd9QaFR9yfYUwH2Lxw');
  }
}
