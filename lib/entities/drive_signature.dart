import 'dart:typed_data';

import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'entities.dart';

class DriveSignatureEntity with TransactionPropertiesMixin {
  String driveId;
  String signatureFormat;
  String cipherIv;
  Uint8List data;

  DriveSignatureEntity({
    required this.driveId,
    required this.signatureFormat,
    required this.cipherIv,
    required this.data,
  });

  static DriveSignatureEntity fromTransaction(
    TransactionCommonMixin transaction,
    Uint8List? data,
  ) {
    try {
      final driveId = transaction.getTag(EntityTag.driveId)!;
      final signatureFormat = transaction.getTag(EntityTag.signatureFormat)!;
      final cipherIv = transaction.getTag(EntityTag.cipherIv)!;

      final driveSignatureEntity = DriveSignatureEntity(
        driveId: driveId,
        signatureFormat: signatureFormat,
        cipherIv: cipherIv,
        data: data!,
      );

      return driveSignatureEntity;
    } catch (e, stacktrace) {
      logger.e(
          'Failed to parse drive signature transaction. driveId: ${transaction.tags.firstWhere((tag) => tag.name == EntityTag.driveId).value}',
          e,
          stacktrace);
      throw EntityTransactionParseException(transactionId: transaction.id);
    }
  }

  Future<DataItem> asPreparedDataItem({
    required ArweaveAddressString owner,
    required AppInfo appInfo,
  }) async {
    final driveSignatureDataItem = DataItem.withBlobData(data: data)
      ..setOwner(owner)
      ..addApplicationTags(
        version: (await PackageInfo.fromPlatform()).version,
      )
      ..addArFsTag()
      ..addTag(EntityTag.entityType, EntityTypeTag.driveSignature)
      ..addTag(EntityTag.driveId, driveId)
      ..addTag(EntityTag.signatureFormat, signatureFormat)
      ..addTag(EntityTag.cipherIv, cipherIv);

    return driveSignatureDataItem;
  }
}
