import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:drift/drift.dart';

import '../services/services.dart';
import 'entity.dart';

class LicenseAssertionTransactionParseException implements Exception {
  final String transactionId;

  LicenseAssertionTransactionParseException({required this.transactionId});
}

const licenseAssertionTxBaseTagKeys = [
  'App-Name',
  'Original',
  'License',
];

class LicenseAssertionEntity with TransactionPropertiesMixin {
  final String dataTxId;
  final String licenseTxId;
  final Map<String, String> additionalTags;

  DateTime blockTimestamp = DateTime.now();

  LicenseAssertionEntity({
    required this.dataTxId,
    required this.licenseTxId,
    this.additionalTags = const {},
  });

  static LicenseAssertionEntity fromTransaction(
    TransactionCommonMixin transaction,
  ) {
    try {
      assert(transaction.getTag('App-Name') == 'License-Assertion');
      final additionalTags = Map.fromEntries(transaction.tags
          .where((tag) => !licenseAssertionTxBaseTagKeys.contains(tag.name))
          .map((tag) => MapEntry(tag.name, tag.value)));
      final licenseAssertionEntity = LicenseAssertionEntity(
        dataTxId: transaction.getTag('Original')!,
        licenseTxId: transaction.getTag('License')!,
        additionalTags: additionalTags,
      )
        ..txId = transaction.id
        ..ownerAddress = transaction.owner.address
        ..bundledIn = transaction.bundledIn?.id;
      if (transaction.block != null) {
        licenseAssertionEntity.blockTimestamp =
            DateTime.fromMillisecondsSinceEpoch(transaction.block!.timestamp);
      }
      return licenseAssertionEntity;
    } catch (_) {
      throw LicenseAssertionTransactionParseException(
        transactionId: transaction.id,
      );
    }
  }

  Future<DataItem> asPreparedDataItem({
    required ArweaveAddressString owner,
  }) async {
    final licenseAssertionDataItem = DataItem.withBlobData(data: Uint8List(0))
      ..setOwner(owner);

    final baseTags = {
      EntityTag.appName: 'License-Assertion',
      'Original': dataTxId,
      'License': licenseTxId,
    };

    baseTags.forEach((key, value) {
      licenseAssertionDataItem.addTag(key, value);
    });

    additionalTags.forEach((key, value) {
      licenseAssertionDataItem.addTag(key, value);
    });

    return licenseAssertionDataItem;
  }
}
