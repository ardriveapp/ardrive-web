import 'package:ardrive/download/limits.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/mocks.dart';

void main() {
  test('Download limits calculated correctly per-platform', () {
    AppPlatform.setMockPlatform(platform: SystemPlatform.Web);
    final MockDeviceInfoPlugin deviceInfo = MockDeviceInfoPlugin();
    when(() => deviceInfo.deviceInfo).thenAnswer(
        (invokation) async => WebBrowserInfo.fromMap({'userAgent': 'Chrome'}));

    expect(calcDownloadSizeLimit(true, deviceInfo: deviceInfo),
        completion(equals(publicDownloadWebSizeLimit)));

    expect(calcDownloadSizeLimit(false, deviceInfo: deviceInfo),
        completion(equals(privateDownloadWebSizeLimit)));

    when(() => deviceInfo.deviceInfo).thenAnswer(
        (invokation) async => WebBrowserInfo.fromMap({'userAgent': 'Firefox'}));

    expect(calcDownloadSizeLimit(true, deviceInfo: deviceInfo),
        completion(equals(publicDownloadFirefoxSizeLimit)));
    expect(calcDownloadSizeLimit(false, deviceInfo: deviceInfo),
        completion(equals(privateDownloadFirefoxSizeLimit)));

    AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

    expect(calcDownloadSizeLimit(true, deviceInfo: deviceInfo),
        completion(equals(publicDownloadMobileSizeLimit)));
    expect(calcDownloadSizeLimit(false, deviceInfo: deviceInfo),
        completion(equals(privateDownloadMobileSizeLimit)));

    AppPlatform.setMockPlatform(platform: SystemPlatform.iOS);

    expect(calcDownloadSizeLimit(true, deviceInfo: deviceInfo),
        completion(equals(publicDownloadMobileSizeLimit)));
    expect(calcDownloadSizeLimit(false, deviceInfo: deviceInfo),
        completion(equals(privateDownloadMobileSizeLimit)));

    AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);

    expect(calcDownloadSizeLimit(true, deviceInfo: deviceInfo),
        completion(equals(publicDownloadUnknownPlatformSizeLimit)));
    expect(calcDownloadSizeLimit(false, deviceInfo: deviceInfo),
        completion(equals(privateDownloadUnknownPlatformSizeLimit)));
  });
}
