import 'dart:convert';

import 'package:ardrive/entities/license_assertion.dart';
import 'package:ardrive/entities/license_composed.dart';
import 'package:ardrive/models/license.dart';
import 'package:drift/drift.dart';

import '../../models/models.dart';
import 'license_state.dart';
import 'licenses/udl.dart';

enum LicenseTxType {
  composed,
  assertion,
}

class LicenseService {
  LicenseType? licenseTypeByTxId(String txId) {
    return licenseMetaMap.entries
        .firstWhere((element) => element.value.licenseDefinitionTxId == txId)
        .key;
  }

  LicenseMeta licenseMetaByType(LicenseType licenseType) {
    return licenseMetaMap[licenseType]!;
  }

  LicenseParams paramsFromAdditionalTags({
    required LicenseType licenseType,
    required Map<String, String>? additionalTags,
  }) {
    switch (licenseType) {
      case LicenseType.udl:
        return UdlLicenseParams.fromAdditionalTags(additionalTags ?? {});
      case LicenseType.ccBy:
        return EmptyParams();
      default:
        throw ArgumentError('Unknown license type: $licenseType');
    }
  }

  LicenseState fromAssertionEntity(
      LicenseAssertionEntity licenseAssertionEntity) {
    final licenseType =
        licenseTypeByTxId(licenseAssertionEntity.licenseDefinitionTxId)!;
    final additionalTags = licenseAssertionEntity.additionalTags;

    return LicenseState(
      meta: licenseMetaByType(licenseType),
      params: paramsFromAdditionalTags(
        licenseType: licenseType,
        additionalTags: additionalTags,
      ),
    );
  }

  LicenseState fromComposedEntity(LicenseComposedEntity licenseComposedEntity) {
    final licenseType =
        licenseTypeByTxId(licenseComposedEntity.licenseDefinitionTxId)!;
    final additionalTags = licenseComposedEntity.additionalTags;

    return LicenseState(
      meta: licenseMetaByType(licenseType),
      params: paramsFromAdditionalTags(
        licenseType: licenseType,
        additionalTags: additionalTags,
      ),
    );
  }

  LicenseState fromCompanion(LicensesCompanion licensesCompanion) {
    final licenseType = licensesCompanion.licenseTypeEnum;
    final Map<String, dynamic> customTags =
        licensesCompanion.customGQLTags.present
            ? jsonDecode(licensesCompanion.customGQLTags.value!)
            : {};

    final additionalTags = customTags.map(
      (key, value) => MapEntry(key, value.toString()),
    );

    return LicenseState(
      meta: licenseMetaByType(licenseType),
      params: paramsFromAdditionalTags(
        licenseType: licenseType,
        additionalTags: additionalTags,
      ),
    );
  }

  LicenseAssertionEntity toEntity({
    required LicenseState licenseState,
    required String dataTxId,
  }) {
    return LicenseAssertionEntity(
      dataTxId: dataTxId,
      licenseDefinitionTxId: licenseState.meta.licenseDefinitionTxId,
      additionalTags: licenseState.params?.toAdditionalTags() ?? {},
    );
  }

  LicensesCompanion toCompanion({
    required LicenseState licenseState,
    required String dataTxId,
    required String fileId,
    required String driveId,
    required String licenseTxId,
    required LicenseTxType licenseTxType,
  }) {
    return LicensesCompanion.insert(
      fileId: fileId,
      driveId: driveId,
      licenseTxId: licenseTxId,
      dataTxId: dataTxId,
      licenseTxType: licenseTxType.name,
      licenseType: licenseState.meta.licenseType.name,
      customGQLTags: licenseState.params != null
          ? Value(jsonEncode(licenseState.params!.toAdditionalTags()))
          : const Value.absent(),
    );
  }
}
