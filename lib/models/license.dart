import 'dart:convert';

import 'package:ardrive/entities/license_assertion.dart';
import 'package:ardrive/entities/license_composed.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:drift/drift.dart';

extension LicensesCompanionExtensions on LicensesCompanion {
  /// Converts the assertion to an instance of [LicenseAssertionEntity].
  LicenseAssertionEntity asAssertionEntity(LicenseService licenseService,
      {required String dataTxId, String? ownerAddress}) {
    final Map<String, String> additionalTags =
        jsonDecode(customGQLTags.value ?? '{}');

    final licenseMeta = licenseService.licenseMetaByType(licenseTypeEnum);
    final licenseAssertion = LicenseAssertionEntity(
      dataTxId: dataTxId,
      licenseDefinitionTxId: licenseMeta.licenseDefinitionTxId,
      additionalTags: additionalTags,
    )
      ..txId = dataTxId
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
  LicensesCompanion toCompanion({
    required LicenseType licenseType,
  }) =>
      LicensesCompanion.insert(
        licenseTxType: LicenseTxType.assertion.name,
        licenseTxId: txId,
        customGQLTags: additionalTags.isNotEmpty
            ? Value(jsonEncode(additionalTags))
            : const Value.absent(),
        dateCreated: Value(blockTimestamp),
        licenseType: licenseType.name,
        bundledIn: bundledIn != null ? Value(bundledIn) : const Value.absent(),
      );
}

extension LicenseComposedEntityExtensions on LicenseComposedEntity {
  /// Converts the entity to an instance of [LicenseAssertionsCompanion].
  LicensesCompanion toCompanion({
    required LicenseType licenseType,
  }) =>
      LicensesCompanion.insert(
        licenseTxType: LicenseTxType.composed.name,
        licenseTxId: txId,
        customGQLTags: additionalTags.isNotEmpty
            ? Value(jsonEncode(additionalTags))
            : const Value.absent(),
        dateCreated: Value(blockTimestamp),
        licenseType: licenseType.name,
        bundledIn: bundledIn == null ? Value(bundledIn) : const Value.absent(),
      );
}
