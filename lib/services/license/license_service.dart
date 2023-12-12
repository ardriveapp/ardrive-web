import 'dart:convert';

import 'package:ardrive/entities/license_assertion.dart';
import 'package:drift/drift.dart';

import '../../models/models.dart';
import 'license_types.dart';
import 'licenses/udl.dart';

class LicenseService {
  LicenseType? licenseTypeByTxId(String txId) {
    return licenseInfo.entries
        .firstWhere((element) => element.value.licenseTxId == txId)
        .key;
  }

  LicenseInfo licenseInfoByType(LicenseType licenseType) {
    return licenseInfo[licenseType]!;
  }

  LicenseParams licenseParamsForType(
    LicenseType licenseType,
    Map<String, String> additionalTags,
  ) {
    switch (licenseType) {
      case LicenseType.udl:
        return UdlLicenseParams.fromAdditionalTags(additionalTags);
      default:
        throw ArgumentError('Unknown license type: $licenseType');
    }
  }

  LicenseAssertionEntity toEntity({
    required String dataTxId,
    required LicenseInfo licenseInfo,
    LicenseParams? licenseParams,
  }) {
    return LicenseAssertionEntity(
      dataTxId: dataTxId,
      licenseTxId: licenseInfo.licenseTxId,
      additionalTags: licenseParams?.toAdditionalTags() ?? {},
    );
  }

  LicenseAssertionsCompanion toCompanion({
    required String dataTxId,
    required LicenseInfo licenseInfo,
    LicenseParams? licenseParams,
  }) {
    return LicenseAssertionsCompanion(
      dataTxId: Value(dataTxId),
      licenseType: Value(licenseInfo.licenseType.name),
      licenseAssertionTxId: Value(licenseInfo.licenseTxId),
      customGQLTags: Value(jsonEncode(licenseParams?.toAdditionalTags() ?? {})),
    );
  }

  LicenseParams paramsFromEntity(
      LicenseAssertionEntity licenseAssertionEntity) {
    switch (licenseTypeByTxId(licenseAssertionEntity.licenseTxId)) {
      case LicenseType.udl:
        return UdlLicenseParams.fromAdditionalTags(
          licenseAssertionEntity.additionalTags,
        );
      default:
        throw ArgumentError(
          'Unknown license type for txId: ${licenseAssertionEntity.licenseTxId}',
        );
    }
  }

  LicenseParams paramsFromCompanion(
      LicenseAssertionsCompanion licenseAssertionsCompanion) {
    final additionalTags =
        jsonDecode(licenseAssertionsCompanion.customGQLTags.value ?? '{}');

    switch (LicenseType.values.firstWhere(
      (element) => element.name == licenseAssertionsCompanion.licenseType.value,
    )) {
      case LicenseType.udl:
        return UdlLicenseParams.fromAdditionalTags(additionalTags);
      default:
        throw ArgumentError(
          'Unknown LicenseType : ${licenseAssertionsCompanion.licenseType.value}',
        );
    }
  }
}
