import 'package:ardrive/utils/logger.dart';
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
  LicenseTag.appName,
  LicenseTag.originalTxId,
  LicenseTag.licenseDefinitionTxId,
];

class LicenseAssertionEntity with TransactionPropertiesMixin {
  final String dataTxId;
  final String licenseDefinitionTxId;
  final Map<String, String> additionalTags;

  DateTime blockTimestamp = DateTime.now();

  LicenseAssertionEntity({
    required this.dataTxId,
    required this.licenseDefinitionTxId,
    this.additionalTags = const {},
  });

  static LicenseAssertionEntity fromTransaction(
    TransactionCommonMixin transaction,
  ) {
    try {
      assert(transaction.getTag(LicenseTag.appName) ==
          LicenseTag.appNameLicenseAssertion);
      final additionalTags = Map.fromEntries(transaction.tags
          .where((tag) => !licenseAssertionTxBaseTagKeys.contains(tag.name))
          .map((tag) => MapEntry(tag.name, tag.value)));
      final licenseAssertionEntity = LicenseAssertionEntity(
        dataTxId: transaction.getTag(LicenseTag.originalTxId)!,
        licenseDefinitionTxId:
            transaction.getTag(LicenseTag.licenseDefinitionTxId)!,
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
    } catch (e, stacktrace) {
      logger.e(
          'Failed to parse license assertion transaction. licenseDefinitionTxId: ${transaction.tags.firstWhere((tag) => tag.name == LicenseTag.licenseDefinitionTxId).value}',
          e,
          stacktrace);
      throw LicenseAssertionTransactionParseException(
        transactionId: transaction.id,
      );
    }
  }

  Future<DataItem> asPreparedDataItem({
    required ArweaveAddressString owner,
    required AppInfo appInfo,
  }) async {
    final ardriveTags = {
      EntityTag.appVersion: appInfo.version,
      EntityTag.appPlatform: appInfo.platform,
      EntityTag.appName: appInfo.appName,
      EntityTag.unixTime:
          (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
    };

    final licenseAssertionDataItem = DataItem.withBlobData(data: Uint8List(0))
      ..setOwner(owner);

    final baseTags = {
      LicenseTag.appName: LicenseTag.appNameLicenseAssertion,
      LicenseTag.originalTxId: dataTxId,
      LicenseTag.licenseDefinitionTxId: licenseDefinitionTxId,
    };

    final tags = [
      ...ardriveTags.entries,
      ...baseTags.entries,
      ...additionalTags.entries
    ];

    for (var tag in tags) {
      licenseAssertionDataItem.addTag(tag.key, tag.value);
    }

    return licenseAssertionDataItem;
  }
}
