import '../license_types.dart';

const udlLicenseInfo = LicenseInfo(
  licenseType: LicenseType.udl,
  licenseTxId: 'yRj4a5KMctX_uOmKWCFJIjmY8DeJcusVk6-HzLiM_t8',
  name: 'Universal Data License',
  shortName: 'UDL',
  version: '1.0',
  hasParams: true,
);

class UdlLicenseParams extends LicenseParams {
  final String? derivations;
  final String? commercialUse;

  UdlLicenseParams({this.derivations, this.commercialUse});

  @override
  Map<String, String> toAdditionalTags() {
    // Null keys should be filtered
    final tags = {
      'Derivation': derivations,
      'Commerical-Use': commercialUse,
    };
    tags.removeWhere((key, value) => value == null);
    return tags.map((key, value) => MapEntry(key, value!));
  }

  static UdlLicenseParams fromAdditionalTags(
    Map<String, String> additionalTags,
  ) {
    return UdlLicenseParams(
      derivations: additionalTags['Derivation'],
      commercialUse: additionalTags['Commerical-Use'],
    );
  }
}
