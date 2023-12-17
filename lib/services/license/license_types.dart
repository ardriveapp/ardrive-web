import 'package:ardrive/services/license/licenses/cc0.dart';

import 'licenses/udl.dart';

enum LicenseType {
  unknown,
  udl,
  ccBy,
}

class LicenseInfo {
  final LicenseType licenseType;
  final String licenseTxId;
  final String name;
  final String shortName;
  final String version;
  final bool hasParams;

  const LicenseInfo({
    required this.licenseType,
    required this.licenseTxId,
    required this.name,
    required this.shortName,
    required this.version,
    this.hasParams = false,
  });
}

abstract class LicenseParams {
  Map<String, String> toAdditionalTags() => {};
}

final licenseInfo = {
  LicenseType.udl: udlLicenseInfo,
  LicenseType.ccBy: ccByLicenseInfo,
};
