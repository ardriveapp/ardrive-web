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
}
