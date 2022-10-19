import 'package:flutter/foundation.dart';
import 'package:platform/platform.dart';

String getPlatform({
  Platform platform = const LocalPlatform(),
  bool isWeb = kIsWeb,
}) {
  if (isWeb) {
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
      return 'unknown';
  }
}

class SystemPlatform {
  static String? _mockPlatform;

  static void setMockPlatform({required String platform}) {
    // TODO: throw if not inside a test (?
    _mockPlatform = platform;
  }

  static String get platform {
    return _mockPlatform ?? getPlatform();
  }
}
