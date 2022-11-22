// ignore_for_file: constant_identifier_names
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/foundation.dart';
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
}

enum SystemPlatform { Android, iOS, Web, unknown }
