import 'dart:convert';

import 'package:ardrive/entities/license_assertion.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/license/license_types.dart';
import 'package:drift/drift.dart';

extension LicenseAssertionsCompanionExtensions on LicenseAssertionsCompanion {
  /// Converts the assertion to an instance of [LicenseAssertionEntity].
  LicenseAssertionEntity asEntity() {
    final Map<String, String> additionalTags =
        jsonDecode(customGQLTags.value ?? '{}');

    final licenseAssertion = LicenseAssertionEntity(
      dataTxId: dataTxId.value,
      licenseTxId: licenseAssertionTxId.value,
      additionalTags: additionalTags,
    )
      ..txId = dataTxId.value
      ..blockTimestamp = dateCreated.value
      ..bundledIn = bundledIn.value;

    if (pinnedDataOwnerAddress.value != null) {
      licenseAssertion.ownerAddress = pinnedDataOwnerAddress.value!.toString();
    }

    return licenseAssertion;
  }

  LicenseType get licenseTypeEnum => LicenseType.values.firstWhere(
        (value) => value.name == licenseType.value,
      );

  /// Returns a list of [NetworkTransactionsCompanion] representing the metadata and data transactions
  /// of this entity.
  List<NetworkTransactionsCompanion> getTransactionCompanions() => [
        NetworkTransactionsCompanion.insert(
            id: licenseAssertionTxId.value, dateCreated: dateCreated),
      ];
}

extension LicenseAssertionEntityExtensions on LicenseAssertionEntity {
  /// Converts the entity to an instance of [LicenseAssertionsCompanion].
  LicenseAssertionsCompanion toLicenseAssertionsCompanion({
    required String fileId,
    required String driveId,
    required LicenseType licenseType,
  }) =>
      LicenseAssertionsCompanion.insert(
        fileId: fileId,
        driveId: driveId,
        dataTxId: dataTxId,
        licenseAssertionTxId: txId,
        dateCreated: Value(blockTimestamp),
        licenseType: licenseType.name,
      );
}
