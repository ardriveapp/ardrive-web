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

  UdlLicenseParams udlParamsFromTags(Map<String, String> tags) {
    return UdlLicenseParams.fromTags(tags);
  }

  LicenseAssertionEntity toLicenseAssertionEntity({
    required String dataTxId,
    required LicenseInfo licenseInfo,
    LicenseParams? licenseParams,
  }) {
    return LicenseAssertionEntity(
      dataTx: dataTxId,
      licenseTx: licenseInfo.licenseTxId,
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
