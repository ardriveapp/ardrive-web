import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'package:platform/platform.dart' as platform;

class AppPlatform {
  static SystemPlatform? _mockPlatform;

  @visibleForTesting
  static void setMockPlatform({required SystemPlatform platform}) {
    _mockPlatform = platform;
  }

  static SystemPlatform getPlatform({
    platform.Platform platform = const platform.LocalPlatform(),
    bool isWeb = kIsWeb,
  }) {
    if (_mockPlatform != null) {
      return _mockPlatform!;
    }

    if (isWeb) {
      return SystemPlatform.Web;
    }

    /// A string (linux, macos, windows, android, ios, or fuchsia) representing the operating system.
    final String operatingSystem = platform.operatingSystem;

    switch (operatingSystem) {
      case 'android':
        return SystemPlatform.Android;
      case 'ios':
        return SystemPlatform.iOS;
      default:
        return SystemPlatform.unknown;
    }
  }

  static bool get isMobile =>
      getPlatform() == SystemPlatform.Android ||
      getPlatform() == SystemPlatform.iOS;

  static bool isMobileWeb() {
    return kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
  }

  static Future<bool> isFireFox({DeviceInfoPlugin? deviceInfo}) async {
    final info = await (deviceInfo ?? DeviceInfoPlugin()).deviceInfo;
    return info is WebBrowserInfo && info.browserName == BrowserName.firefox;
  }
}

// ignore: constant_identifier_names
enum SystemPlatform { Android, iOS, Web, unknown }
