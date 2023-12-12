import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:drift/drift.dart';

import '../services/services.dart';

class LicenseAssertionTransactionParseException implements Exception {
  final String transactionId;

  LicenseAssertionTransactionParseException({required this.transactionId});
}

const licenseAssertionTxBaseTagKeys = [
  'App-Name',
  'Original',
  'License',
];

class LicenseAssertionEntity {
  final String dataTx;
  final String licenseTx;
  final Map<String, String> additionalTags;

  LicenseAssertionEntity({
    required this.dataTx,
    required this.licenseTx,
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
      return LicenseAssertionEntity(
        dataTx: transaction.getTag('Original')!,
        licenseTx: transaction.getTag('License')!,
        additionalTags: additionalTags,
      );
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
      'Original': dataTx,
      'License': licenseTx,
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
