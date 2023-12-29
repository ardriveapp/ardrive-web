import 'dart:convert';

import 'package:ardrive/entities/license_assertion.dart';
import 'package:drift/drift.dart';

import '../../models/models.dart';
import 'license_types.dart';
import 'licenses/udl.dart';

enum LicenseTxType {
  bundled,
  assertion,
}

class LicenseService {
  LicenseType? licenseTypeByTxId(String txId) {
    return licenseInfoMap.entries
        .firstWhere((element) => element.value.licenseDefinitionTxId == txId)
        .key;
  }

  LicenseInfo licenseInfoByType(LicenseType licenseType) {
    return licenseInfoMap[licenseType]!;
  }

  LicenseParams paramsFromAdditionalTags({
    required LicenseType licenseType,
    required Map<String, String> additionalTags,
  }) {
    switch (licenseType) {
      case LicenseType.udl:
        return UdlLicenseParams.fromAdditionalTags(additionalTags);
      default:
        throw ArgumentError('Unknown license type: $licenseType');
    }
  }

  LicenseParams paramsFromEntity(
      LicenseAssertionEntity licenseAssertionEntity) {
    final licenseType =
        licenseTypeByTxId(licenseAssertionEntity.licenseDefinitionTxId)!;
    final additionalTags = licenseAssertionEntity.additionalTags;

    return paramsFromAdditionalTags(
      licenseType: licenseType,
      additionalTags: additionalTags,
    );
  }

  LicenseParams paramsFromCompanion(LicensesCompanion licensesCompanion) {
    final licenseType = LicenseType.values.firstWhere(
      (element) => element.name == licensesCompanion.licenseType.value,
    );
    final additionalTags = licensesCompanion.customGQLTags.present
        ? jsonDecode(licensesCompanion.customGQLTags.value!)
        : {};

    return paramsFromAdditionalTags(
      licenseType: licenseType,
      additionalTags: additionalTags,
    );
  }

  LicenseAssertionEntity toEntity({
    required String dataTxId,
    required LicenseInfo licenseInfo,
    LicenseParams? licenseParams,
  }) {
    return LicenseAssertionEntity(
      dataTxId: dataTxId,
      licenseDefinitionTxId: licenseInfo.licenseDefinitionTxId,
      additionalTags: licenseParams?.toAdditionalTags() ?? {},
    );
  }

  LicensesCompanion toCompanion({
    required String dataTxId,
    required LicenseInfo licenseInfo,
    LicenseParams? licenseParams,
  }) {
    return LicensesCompanion(
      dataTxId: Value(dataTxId),
      licenseType: Value(licenseInfo.licenseType.name),
      customGQLTags: licenseParams != null
          ? Value(jsonEncode(licenseParams.toAdditionalTags()))
          : const Value.absent(),
    );
  }
}
