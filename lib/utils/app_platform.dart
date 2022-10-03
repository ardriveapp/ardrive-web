import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:platform/platform.dart';

getPlatform({Platform platform = const LocalPlatform()}) {
  if (kIsWeb) {
    return 'Web';
  }

  /// A string (linux, macos, windows, android, ios, or fuchsia) representing the operating system.
  final String operatingSystem = platform.operatingSystem;

  switch (operatingSystem) {
    case 'android':
      return 'Android';
    case 'ios':
      return 'iOS';
    default:
      throw Exception('Unsupported platform $operatingSystem!');
  }
}

// TODO: PE-2380
getPlatformVersion() async {
  final platform = getPlatform();
  final deviceInfoPlugin = DeviceInfoPlugin();

  switch (platform) {
    case 'Android':
      final androidDeviceInfo = await deviceInfoPlugin.androidInfo;
      final String? androidVersion = androidDeviceInfo.version.release;
      final int? sdkVersion = androidDeviceInfo.version.sdkInt;
      final versionString = '$androidVersion (SDK $sdkVersion)';

      return versionString;

    case 'iOS':
      final iosDeviceInfo = await deviceInfoPlugin.iosInfo;
      final String? systemName = iosDeviceInfo.systemName;
      final String? iosVersion = iosDeviceInfo.systemVersion;
      final versionString = '$systemName $iosVersion';

      return versionString;

    default: // case 'Web':
      final webDeviceInfo = await deviceInfoPlugin.webBrowserInfo;
      final browserName = describeEnum(webDeviceInfo.browserName);
      final browserVersion = webDeviceInfo.appVersion;
      final versionString = '$browserName $browserVersion';

      return versionString;
  }
}
