import 'dart:convert';

import 'package:ardrive/entities/license_assertion.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/license/license_types.dart';
import 'package:ardrive/services/services.dart';
import 'package:drift/drift.dart';

extension LicensesCompanionExtensions on LicensesCompanion {
  /// Converts the assertion to an instance of [LicenseAssertionEntity].
  LicenseAssertionEntity asEntity(LicenseService licenseService,
      {String? ownerAddress}) {
    final Map<String, String> additionalTags =
        jsonDecode(customGQLTags.value ?? '{}');

    final licenseInfo = licenseService.licenseInfoByType(licenseTypeEnum);
    final licenseAssertion = LicenseAssertionEntity(
      dataTxId: dataTxId.value,
      licenseDefinitionTxId: licenseInfo.licenseDefinitionTxId,
      additionalTags: additionalTags,
    )
      ..txId = dataTxId.value
      ..blockTimestamp = dateCreated.value
      ..bundledIn = bundledIn.value;

    if (ownerAddress != null) {
      licenseAssertion.ownerAddress = ownerAddress;
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
            id: licenseTxId.value, dateCreated: dateCreated),
      ];
}

extension LicenseAssertionEntityExtensions on LicenseAssertionEntity {
  /// Converts the entity to an instance of [LicenseAssertionsCompanion].
  LicensesCompanion toLicensesCompanion({
    required String fileId,
    required String driveId,
    required LicenseType licenseType,
  }) =>
      LicensesCompanion.insert(
        fileId: fileId,
        driveId: driveId,
        dataTxId: dataTxId,
        licenseTxType: LicenseTxType.assertion.name,
        licenseTxId: txId,
        dateCreated: Value(blockTimestamp),
        licenseType: licenseType.name,
      );
}
