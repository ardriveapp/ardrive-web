import 'licenses/udl.dart';

enum LicenseType {
  unknown,
  udl,
}

class LicenseInfo {
  final LicenseType licenseType;
  final String licenseTxId;
  final String name;
  final String shortName;
  final String version;

  const LicenseInfo({
    required this.licenseType,
    required this.licenseTxId,
    required this.name,
    required this.shortName,
    required this.version,
  });
}

abstract class LicenseParams {
  Map<String, String> toAdditionalTags() => {};
}

final licenseInfo = {
  LicenseType.udl: udlLicenseInfo,
};
