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

  /// The app's version and platform, once [loadAppInfo] has finished.
  ///
  /// Throws a [StateError] before then. Anything that runs well after the
  /// start awaits [loadAppInfo] (or reads [getAppInfo]) first: the start does
  /// not wait for it, and if version.json could not be read then, only a later
  /// load gets the version for the rest of the session.
  AppInfo get appInfo {
    if (_appInfo == null) {
      throw StateError('AppInfoServices has not been initialized');
    }

    return _appInfo!;
  }

  /// [appInfo], loading it first if it is not loaded yet, or trying again if
  /// the last load failed.
  Future<AppInfo> getAppInfo() async {
    await loadAppInfo();
    return appInfo;
  }

  AppInfo? _appInfo;
  Future<void>? _loading;

  /// Loads [appInfo] once; a call while it loads joins that load, and a
  /// failed load is tried again by the next call.
  Future<void> loadAppInfo() => _loading ??= _load().then(
        (_) {},
        onError: (Object e, StackTrace s) {
          _loading = null;
          return Future<void>.error(e, s);
        },
      );

  Future<void> _load() async {
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
