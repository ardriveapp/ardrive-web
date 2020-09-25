import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:json_annotation/json_annotation.dart';

import 'entities.dart';

abstract class Entity {
  @JsonKey(ignore: true)
  String ownerAddress;
  @JsonKey(ignore: true)
  DateTime commitTime;

  /// Returns a transaction with the entity's data along with the appropriate tags.
  ///
  /// If a key is provided, the transaction data is encrypted.
  Future<Transaction> asTransaction([SecretKey key]);
}

extension TransactionUtils on Transaction {
  void addApplicationTags() {
    addTag(EntityTag.appName, 'drive');
    addTag(EntityTag.appVersion, '0.11.0');
    addTag(
        EntityTag.unixTime, DateTime.now().millisecondsSinceEpoch.toString());
  }
}
