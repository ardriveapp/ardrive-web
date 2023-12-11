import 'licenses/udl.dart';

enum LicenseType {
  unknown,
  udl,
}

class LicenseInfo {
  final String licenseTxId;
  final String name;
  final String shortName;
  final String version;

  LicenseInfo({
    required this.licenseTxId,
    required this.name,
    required this.shortName,
    required this.version,
  });
}

class LicenseParams {
  Map<String, String> toAdditionalTags() => {};
}

final licenseInfo = {
  LicenseType.udl: udlLicenseInfo,
};
