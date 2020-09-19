import 'package:arweave/arweave.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:pointycastle/export.dart';

abstract class Entity {
  @JsonKey(ignore: true)
  String ownerAddress;
  @JsonKey(ignore: true)
  DateTime commitTime;

  /// Returns a transaction with the entity's data along with the appropriate tags.
  ///
  /// If a key is provided, the transaction data is encrypted.
  Future<Transaction> asTransaction([KeyParameter key]);
}
