import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

import 'entities.dart';

abstract class Entity {
  /// The id of the transaction that represents this entity.
  @JsonKey(ignore: true)
  String? txId;

  /// The address of the owner of this entity.
  @JsonKey(ignore: true)
  String? ownerAddress;

  /// The time this entity was created at ie. its `Unix-Time`.
  @JsonKey(ignore: true)
  DateTime createdAt = DateTime.now();

  /// Returns a [Transaction] with the entity's data along with the appropriate tags.
  ///
  /// If a key is provided, the transaction data is encrypted.
  Future<Transaction> asTransaction([SecretKey? key]) async {
    final tx = key == null
        ? Transaction.withJsonData(data: this)
        : await createEncryptedEntityTransaction(this, key);

    addEntityTagsToTransaction(tx);

    return tx;
  }

  /// Returns a [DataItem] with the entity's data along with the appropriate tags.
  ///
  /// The `owner` on this [DataItem] will be unset.
  ///
  /// If a key is provided, the data item data is encrypted.
  Future<DataItem> asDataItem([SecretKey? key]) async {
    final item = key == null
        ? DataItem.withJsonData(data: this)
        : await createEncryptedEntityDataItem(this, key);

    addEntityTagsToTransaction(item);

    return item;
  }

  @protected
  void addEntityTagsToTransaction<T extends TransactionBase>(T tx);
}

class EntityTransactionParseException implements Exception {}

extension TransactionUtils on TransactionBase {
  /// Tags this transaction with the app name, version, and the specified unix time.
  void addApplicationTags({DateTime? unixTime}) {
    addTag(EntityTag.appName, 'ArDrive-Web');
    addTag(EntityTag.appVersion, '0.1.0');
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
