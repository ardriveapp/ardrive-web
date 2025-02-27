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

  static bool get isAndroid => getPlatform() == SystemPlatform.Android;

  static Future<String?> androidVersion({
    DeviceInfoPlugin? deviceInfo,
  }) async {
    final info = await (deviceInfo ?? DeviceInfoPlugin()).deviceInfo;
    return info is AndroidDeviceInfo ? info.version.release : null;
  }

  static bool get isIos => getPlatform() == SystemPlatform.iOS;

  static Future<String?> iosVersion({
    DeviceInfoPlugin? deviceInfo,
  }) async {
    final info = await (deviceInfo ?? DeviceInfoPlugin()).deviceInfo;
    return info is IosDeviceInfo ? info.systemVersion : null;
  }

  static bool get isMobile =>
      getPlatform() == SystemPlatform.Android ||
      getPlatform() == SystemPlatform.iOS;

  static bool isWeb() {
    return _mockPlatform == SystemPlatform.Web || kIsWeb;
  }

  static bool isMobileWeb() {
    return kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
  }

  static bool isWindows() {
    return getPlatform() == SystemPlatform.Windows;
  }

  static Future<bool> isFireFox({DeviceInfoPlugin? deviceInfo}) async {
    final info = await (deviceInfo ?? DeviceInfoPlugin()).deviceInfo;
    return info is WebBrowserInfo && info.browserName == BrowserName.firefox;
  }

  static Future<bool> isChrome({DeviceInfoPlugin? deviceInfo}) async {
    final info = await (deviceInfo ?? DeviceInfoPlugin()).deviceInfo;
    return info is WebBrowserInfo && info.browserName == BrowserName.chrome;
  }

  static Future<bool> isSafari({DeviceInfoPlugin? deviceInfo}) async {
    final info = await (deviceInfo ?? DeviceInfoPlugin()).deviceInfo;
    return info is WebBrowserInfo && info.browserName == BrowserName.safari;
  }

  static Future<String?> browserVersion({DeviceInfoPlugin? deviceInfo}) async {
    final info = await (deviceInfo ?? DeviceInfoPlugin()).deviceInfo;
    if (info is WebBrowserInfo) {
      final userAgent = info.userAgent;

      if (userAgent == null) return null;

      if (userAgent.contains('Firefox/')) {
        return 'Firefox ${userAgent.split('Firefox/')[1]}';
      } else if (userAgent.contains('Chrome/')) {
        return 'Chrome ${userAgent.split('Chrome/')[1].split(' ')[0]}';
      } else if (userAgent.contains('Safari/')) {
        return 'Safari ${userAgent.split('Version/')[1].split(' ')[0]}';
      } else {
        return null;
      }
    }

    return null;
  }
}

// ignore: constant_identifier_names
enum SystemPlatform { Android, iOS, Web, unknown, Windows }
