import 'package:ardrive/entities/license_assertion.dart';

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

  LicenseAssertionEntity toLicenseAssertionEntity({
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

  LicenseAssertionsCompanion toLicenseAssertionModel(
    LicenseAssertionEntity licenseAssertionEntity,
  ) {
    // TODO: implement toLicenseAssertionModel
    throw UnimplementedError('TODO: implement toLicenseAssertionModel');
  }
}
