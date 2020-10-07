import 'package:ardrive/services/crypto/entities.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

import 'entities.dart';

abstract class Entity {
  @JsonKey(ignore: true)
  String ownerAddress;
  @JsonKey(ignore: true)
  DateTime commitTime;

  /// Returns a transaction with the entity's data along with the appropriate tags.
  ///
  /// If a key is provided, the transaction data is encrypted.
  ///
  /// Throws an [EntityTransactionParseException] if the transaction represents an invalid entity.
  Future<Transaction> asTransaction([SecretKey key]);

  @protected
  static Future handleTransactionDecryptionException(Object err) =>
      err is TransactionDecryptionException
          ? Future.error(EntityTransactionParseException())
          : null;
}

class EntityTransactionParseException implements Exception {}

extension TransactionUtils on Transaction {
  void addApplicationTags() {
    addTag(EntityTag.appName, 'ArDrive-Web');
    addTag(EntityTag.appVersion, '0.1.0');
    addTag(
        EntityTag.unixTime, DateTime.now().millisecondsSinceEpoch.toString());
  }

  void addArFsTag() {
    addTag(EntityTag.arFs, '0.10');
  }
}
