import 'package:ardrive/services/license/license_state.dart';
import 'package:test/test.dart';

void main() {
  group('License Meta Map', () {
    test('should contain all LicenseType enum values', () {
      // Iterate over all LicenseType values
      for (var type in LicenseType.values) {
        if (type == LicenseType.unknown) continue;
        // Check if the licenseMetaMap contains the current enum value
        expect(licenseMetaMap.containsKey(type), isTrue,
            reason: 'Missing meta for $type');
      }
    });

    test('should not contain unknown LicenseType in map', () {
      // Verify the 'unknown' LicenseType is not in the map
      expect(licenseMetaMap.containsKey(LicenseType.unknown), isFalse,
          reason: 'Map should not contain meta for unknown license type');
    });
  });

  group(
      'Ensure we wont change a licenseDefinitionTxId of existing licenses meta',
      () {
    test(
        'cc0',
        () => expect(licenseMetaMap[LicenseType.cc0]!.licenseDefinitionTxId,
            'nF6Mjy_Yy_Gv-DYLq7QPxz5PdXUQ4rtOpbJZdcaFEKw'));

    test(
        'ccBy v1',
        () => expect(licenseMetaMap[LicenseType.ccBy]!.licenseDefinitionTxId,
            'rz2DNzn9pnYOU6049Wm6V7kr0BhyfWE6ZD_mqrXMv5A'));

    test(
        'ccBy v2',
        () => expect(licenseMetaMap[LicenseType.ccByV2]!.licenseDefinitionTxId,
            'mSOFUrl5mUQvG7VBP36DD39kzJASv9FDe3GxHpcCvRA'));

    test(
        'ccByNC',
        () => expect(licenseMetaMap[LicenseType.ccByNC]!.licenseDefinitionTxId,
            '9jG6a1fWgQ_wE4R6OGA2Xg9vGRAwpkrQIMC83nC3kvI'));

    test(
        'ccByNCND',
        () => expect(
            licenseMetaMap[LicenseType.ccByNCND]!.licenseDefinitionTxId,
            'OlTlW1xEw75UC0cdmNqvxc3j6iAmFXrS4usWIBfu_3E'));

    test(
        'ccByNCSA',
        () => expect(
            licenseMetaMap[LicenseType.ccByNCSA]!.licenseDefinitionTxId,
            '2PO2MDRNZLJjgA_0hNGUAD7yXg9nneq-3fxTTLP-uo8'));

    test(
        'ccByND',
        () => expect(licenseMetaMap[LicenseType.ccByND]!.licenseDefinitionTxId,
            'XaIMRBMNqTUlHa_hzypkopfRFyAKqit-AWo-OxwIxoo'));

    test(
        'ccBySA',
        () => expect(licenseMetaMap[LicenseType.ccBySA]!.licenseDefinitionTxId,
            'sKz-PZ96ApDoy5RTBspxhs1GP-cHommw4_9hEiZ6K3c'));

    test(
        'udl',
        () => expect(licenseMetaMap[LicenseType.udl]!.licenseDefinitionTxId,
            'yRj4a5KMctX_uOmKWCFJIjmY8DeJcusVk6-HzLiM_t8'));

    test(
        'udlV2',
        () => expect(licenseMetaMap[LicenseType.udlV2]!.licenseDefinitionTxId,
            'IVjAM1C3x3GFdc3t9EqMnbtGnpgTuJbaiYZa1lk09_8'));
  });
}
