import '../license_state.dart';

List<LicenseMeta> ccLicenses = [
  cc0LicenseMeta,
  ccByLicenseMetaV2,
  ccByNCLicenseMeta,
  ccByNCNDLicenseMeta,
  ccByNCSAMeta,
  ccByNDLicenseMeta,
  ccBySAMeta,
];

const cc0LicenseMeta = LicenseMeta(
  licenseType: LicenseType.cc0,
  licenseDefinitionTxId: 'nF6Mjy_Yy_Gv-DYLq7QPxz5PdXUQ4rtOpbJZdcaFEKw',
  name: 'Public Domain',
  shortName: 'CC0',
);

// Version 4.0
const ccByLicenseMeta = LicenseMeta(
  licenseType: LicenseType.ccBy,
  licenseDefinitionTxId: 'rz2DNzn9pnYOU6049Wm6V7kr0BhyfWE6ZD_mqrXMv5A',
  name: 'Attribution',
  shortName: 'CC-BY',
  hasParams: true,
);

const ccByLicenseMetaV2 = LicenseMeta(
  licenseType: LicenseType.ccByV2,
  licenseDefinitionTxId: 'mSOFUrl5mUQvG7VBP36DD39kzJASv9FDe3GxHpcCvRA',
  name: 'Attribution',
  shortName: 'CC-BY',
  hasParams: true,
);

// Version 4.0
const ccByNCLicenseMeta = LicenseMeta(
  licenseType: LicenseType.ccByNC,
  licenseDefinitionTxId: '9jG6a1fWgQ_wE4R6OGA2Xg9vGRAwpkrQIMC83nC3kvI',
  name: 'Attribution Non-Commercial',
  shortName: 'CC-BY-NC',
);

// Version 4.0
const ccByNCNDLicenseMeta = LicenseMeta(
  licenseType: LicenseType.ccByNCND,
  licenseDefinitionTxId: 'OlTlW1xEw75UC0cdmNqvxc3j6iAmFXrS4usWIBfu_3E',
  name: 'Attribution Non-Commercial No-Derivatives',
  shortName: 'CC-BY-NC-ND',
);

// Version 4.0
const ccByNCSAMeta = LicenseMeta(
  licenseType: LicenseType.ccByNCSA,
  licenseDefinitionTxId: '2PO2MDRNZLJjgA_0hNGUAD7yXg9nneq-3fxTTLP-uo8',
  name: 'Attribution Non-Commercial Share-A-Like',
  shortName: 'CC-BY-NC-SA',
);

// Version 4.0
const ccByNDLicenseMeta = LicenseMeta(
  licenseType: LicenseType.ccByND,
  licenseDefinitionTxId: 'XaIMRBMNqTUlHa_hzypkopfRFyAKqit-AWo-OxwIxoo',
  name: 'Attribution No-Derivatives',
  shortName: 'CC-BY-ND',
);

// Version 4.0
const ccBySAMeta = LicenseMeta(
  licenseType: LicenseType.ccBySA,
  licenseDefinitionTxId: 'sKz-PZ96ApDoy5RTBspxhs1GP-cHommw4_9hEiZ6K3c',
  name: 'Attribution Share-A-Like',
  shortName: 'CC-BY-SA',
);
