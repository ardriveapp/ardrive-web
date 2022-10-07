import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'entities.dart';

abstract class Entity {
  /// The id of the transaction that represents this entity.
  @JsonKey(ignore: true)
  late String txId;

  /// The address of the owner of this entity.
  @JsonKey(ignore: true)
  late String ownerAddress;

  /// The bundle this entity is a part of.
  @JsonKey(ignore: true)
  String? bundledIn;

  /// The time this entity was created at ie. its `Unix-Time`.
  @JsonKey(ignore: true)
  DateTime createdAt = DateTime.now();

  /// Returns a [Transaction] with the entity's data along with the appropriate tags.
  ///
  /// If a key is provided, the transaction data is encrypted.
  Future<Transaction> asTransaction({
    SecretKey? key,
    required String platform,
  }) async {
    final tx = key == null
        ? Transaction.withJsonData(data: this)
        : await createEncryptedEntityTransaction(this, key);
    final packageInfo = await PackageInfo.fromPlatform();

    addEntityTagsToTransaction(tx);

    tx.addApplicationTags(
      version: packageInfo.version,
      unixTime: createdAt,
      platform: platform,
    );
    return tx;
  }

  /// Returns a [DataItem] with the entity's data along with the appropriate tags.
  ///
  /// The `owner` on this [DataItem] will be unset.
  ///
  /// If a key is provided, the data item data is encrypted.
  Future<DataItem> asDataItem(
    SecretKey? key, {
    required String platform,
  }) async {
    final item = key == null
        ? DataItem.withJsonData(data: this)
        : await createEncryptedEntityDataItem(this, key);
    final packageInfo = await PackageInfo.fromPlatform();
    addEntityTagsToTransaction(item);
    item.addApplicationTags(
      version: packageInfo.version,
      platform: platform,
    );

    return item;
  }

  @protected
  void addEntityTagsToTransaction<T extends TransactionBase>(T tx);
}

class EntityTransactionParseException implements Exception {
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
    required String platform,
    bool isWeb = kIsWeb,
  }) {
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
    addTag(EntityTag.arFs, '0.11');
  }
}
