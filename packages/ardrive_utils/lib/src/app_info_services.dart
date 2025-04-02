import 'package:ardrive_utils/src/app_platform.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppInfo {
  final String version;
  final String arfsVersion;
  final String appName;
  final String platform;

  AppInfo({
    required this.version,
    required this.appName,
    required this.platform,
    required this.arfsVersion,
  });
}

class AppInfoServices {
  static final AppInfoServices _instance = AppInfoServices._internal();

  factory AppInfoServices() {
    return _instance;
  }

  AppInfoServices._internal();

  AppInfo get appInfo {
    if (_appInfo == null) {
      throw StateError('AppInfoServices has not been initialized');
    }

    return _appInfo!;
  }

  AppInfo? _appInfo;

  Future<void> loadAppInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final appPlatform = AppPlatform.getPlatform().name;

    _appInfo = AppInfo(
      version: packageInfo.version,
      appName: appName,
      platform: appPlatform,
      arfsVersion: arfsVersion,
    );
  }
}

const String appName = 'ArDrive-App';
const String arfsVersion = '0.15';
