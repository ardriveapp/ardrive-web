import 'package:ardrive/utils/app_platform.dart';
import 'package:platform/platform.dart';
import 'package:test/test.dart';

void main() {
  final androidFakePlatform = FakePlatform(operatingSystem: 'android');
  final iOSFakePlatform = FakePlatform(operatingSystem: 'ios');
  final unknownFakePlatform =
      FakePlatform(operatingSystem: 'not something we know');

  group('getPlatform method', () {
    test('returns "Web" for browser platforms', () {
      final platformString =
          getPlatform(platform: unknownFakePlatform, isWeb: true);
      expect(platformString, 'Web');
    });

    test('returns "Android" for Android devices', () {
      final platformString =
          getPlatform(platform: androidFakePlatform, isWeb: false);
      expect(platformString, 'Android');
    });

    test('returns "iOS" for iOS devices', () {
      final platformString =
          getPlatform(platform: iOSFakePlatform, isWeb: false);
      expect(platformString, 'iOS');
    });

    test('returns "unknown" when the device cannot be determined', () {
      final platformString =
          getPlatform(platform: unknownFakePlatform, isWeb: false);
      expect(platformString, 'unknown');
    });
  });

  group('SystemPlatform class', () {
    test('will call getPlatform if not mocked', () {
      expect(SystemPlatform.platform, 'unknown');
    });

    test('can mock the platform string', () {
      SystemPlatform.setMockPlatform(platform: 'abcdefg');
      expect(SystemPlatform.platform, 'abcdefg');
    });
  });
}
