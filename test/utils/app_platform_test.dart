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
      final platform =
          AppPlatform.getPlatform(platform: unknownFakePlatform, isWeb: true);
      expect(platform, SystemPlatform.Web);
    });

    test('returns Android for Android devices', () {
      final platform =
          AppPlatform.getPlatform(platform: androidFakePlatform, isWeb: false);
      expect(platform, SystemPlatform.Android);
    });

    test('returns iOS for iOS devices', () {
      final platform =
          AppPlatform.getPlatform(platform: iOSFakePlatform, isWeb: false);
      expect(platform, SystemPlatform.iOS);
    });

    test('returns unknown when the device cannot be determined', () {
      final platform =
          AppPlatform.getPlatform(platform: unknownFakePlatform, isWeb: false);
      expect(platform, SystemPlatform.unknown);
    });
  });

  group('Testing setMockPlatform method', () {
    test('return the mocked platform', () {
      AppPlatform.setMockPlatform(platform: SystemPlatform.iOS);
      expect(AppPlatform.getPlatform(), SystemPlatform.iOS);

      AppPlatform.setMockPlatform(platform: SystemPlatform.Android);
      expect(AppPlatform.getPlatform(), SystemPlatform.Android);

      AppPlatform.setMockPlatform(platform: SystemPlatform.Web);
      expect(AppPlatform.getPlatform(), SystemPlatform.Web);

      AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);
      expect(AppPlatform.getPlatform(), SystemPlatform.unknown);
    });
  });

  group('Testing isMobile method', () {
    test('should return true when android', () {
      AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

      expect(AppPlatform.isMobile, true);
    });
    test('should return true when ios', () {
      AppPlatform.setMockPlatform(platform: SystemPlatform.iOS);

      expect(AppPlatform.isMobile, true);
    });
    test('should return false when web', () {
      AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

      expect(AppPlatform.isMobile, false);
    });
    test('should return false when unknown', () {
      AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);

      expect(AppPlatform.isMobile, false);
    });
  });
}
