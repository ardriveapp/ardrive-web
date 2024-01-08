import 'package:ardrive/services/license/licenses/cc0.dart';

import 'licenses/udl.dart';

enum LicenseType {
  unknown,
  udl,
  ccBy,
}

class LicenseMeta {
  final LicenseType licenseType;
  final String licenseDefinitionTxId;
  final String name;
  final String shortName;
  final String version;
  final bool hasParams;

  const LicenseMeta({
    required this.licenseType,
    required this.licenseDefinitionTxId,
    required this.name,
    required this.shortName,
    required this.version,
    this.hasParams = false,
  });
}

class LicenseParams {
  Map<String, String> toAdditionalTags() => {};
}

class EmptyParams extends LicenseParams {}

final licenseMetaMap = {
  LicenseType.udl: udlLicenseMeta,
  LicenseType.ccBy: ccByLicenseMeta,
};

class LicenseState {
  final LicenseMeta meta;
  final LicenseParams? params;

  const LicenseState({
    required this.meta,
    this.params,
  });
}
