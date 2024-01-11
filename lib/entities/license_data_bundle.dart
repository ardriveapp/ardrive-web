import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:drift/drift.dart';

import '../services/services.dart';
import 'entity.dart';

class LicenseDataBundleTransactionParseException implements Exception {
  final String transactionId;

  LicenseDataBundleTransactionParseException({required this.transactionId});
}

const licenseDataBundleTxBaseTagKeys = [
  LicenseTag.licenseDefinitionTxId,
];

const arfsDataTxBaseTagKeys = [
  EntityTag.appName,
  EntityTag.appVersion,
  EntityTag.appPlatform,
  EntityTag.unixTime,
  EntityTag.contentType,
];

final additionalTagKeysBlacklist =
    licenseDataBundleTxBaseTagKeys + arfsDataTxBaseTagKeys;

class LicenseDataBundleEntity with TransactionPropertiesMixin {
  final String licenseDefinitionTxId;
  final Map<String, String> additionalTags;
  // final Map<String, String> arfsTags;

  DateTime blockTimestamp = DateTime.now();

  LicenseDataBundleEntity({
    required this.licenseDefinitionTxId,
    this.additionalTags = const {},
    // this.arfsTags = const {},
  });

  static LicenseDataBundleEntity fromTransaction(
    TransactionCommonMixin transaction,
  ) {
    try {
      final additionalTags = Map.fromEntries(transaction.tags
          .where((tag) => !additionalTagKeysBlacklist.contains(tag.name))
          .map((tag) => MapEntry(tag.name, tag.value)));
      final licenseDataBundleEntity = LicenseDataBundleEntity(
        licenseDefinitionTxId:
            transaction.getTag(LicenseTag.licenseDefinitionTxId)!,
        additionalTags: additionalTags,
      )
        ..txId = transaction.id
        ..ownerAddress = transaction.owner.address
        ..bundledIn = transaction.bundledIn?.id;

      if (transaction.block != null) {
        licenseDataBundleEntity.blockTimestamp =
            DateTime.fromMillisecondsSinceEpoch(transaction.block!.timestamp);
      }
      return licenseDataBundleEntity;
    } catch (_) {
      throw LicenseDataBundleTransactionParseException(
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
      LicenseTag.licenseDefinitionTxId: licenseDefinitionTxId,
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
