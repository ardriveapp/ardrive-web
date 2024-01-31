import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:drift/drift.dart';

import '../services/services.dart';
import 'entity.dart';

class LicenseComposedTransactionParseException implements Exception {
  final String transactionId;

  LicenseComposedTransactionParseException({required this.transactionId});
}

const licenseComposedTxBaseTagKeys = [
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
    licenseComposedTxBaseTagKeys + arfsDataTxBaseTagKeys;

class LicenseComposedEntity with TransactionPropertiesMixin {
  final String licenseDefinitionTxId;
  final Map<String, String> additionalTags;

  DateTime blockTimestamp = DateTime.now();

  LicenseComposedEntity({
    required this.licenseDefinitionTxId,
    this.additionalTags = const {},
  });

  static LicenseComposedEntity fromTransaction(
    TransactionCommonMixin transaction,
  ) {
    try {
      final additionalTags = Map.fromEntries(transaction.tags
          .where((tag) => !additionalTagKeysBlacklist.contains(tag.name))
          .map((tag) => MapEntry(tag.name, tag.value)));
      final licenseComposedEntity = LicenseComposedEntity(
        licenseDefinitionTxId:
            transaction.getTag(LicenseTag.licenseDefinitionTxId)!,
        additionalTags: additionalTags,
      )
        ..txId = transaction.id
        ..ownerAddress = transaction.owner.address
        ..bundledIn = transaction.bundledIn?.id;

      if (transaction.block != null) {
        licenseComposedEntity.blockTimestamp =
            DateTime.fromMillisecondsSinceEpoch(transaction.block!.timestamp);
      }
      return licenseComposedEntity;
    } catch (_) {
      throw LicenseComposedTransactionParseException(
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
