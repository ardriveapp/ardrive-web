import 'package:ardrive/services/config/config_fetcher.dart';
import 'package:ardrive/utils/app_flavors.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';

import 'config.dart';

// TODO: Add arnsResolverUrl to AppConfig for configurable ARNS resolver base URL.
class ConfigService {
  ConfigService({
    required ConfigFetcher configFetcher,
    required AppFlavors appFlavors,
  })  : _configFetcher = configFetcher,
        _appFlavors = appFlavors;

  final ConfigFetcher _configFetcher;
  final AppFlavors _appFlavors;

  AppConfig? _config;
  Flavor? _flavor;

  AppConfig get config {
    if (_config == null) {
      throw Exception('Config not loaded');
    }

    return _config!;
  }

  Flavor get flavor {
    if (_flavor == null) {
      throw Exception('Flavor not loaded');
    }

    return _flavor!;
  }

  Future<AppConfig> loadConfig() async {
    _config ??= await _configFetcher.fetchConfig(await loadAppFlavor());
    // Names read and write through the ARIO SDK's web bridge: elsewhere
    // every call throws. Not saved, so a later build that has it gets it.
    if (_config!.enableArNS && !isArioSDKSupportedOnPlatform()) {
      _config = _config!.copyWith(enableArNS: false);
    }

    logger.d('App config: $_config');

    return _config!;
  }

  Future<Flavor> loadAppFlavor() async {
    try {
      _flavor = await _appFlavors.getAppFlavor();

      logger.i('App flavor: $flavor');

      return flavor;
    } catch (e, stacktrace) {
      logger.e('An issue occured when loading flavors.', e, stacktrace);

      return Flavor.production;
    }
  }

  /// The config this flavor ships with, before anything was changed on this
  /// device. Read from the asset each time: it is only asked for by Settings.
  Future<AppConfig> loadDefaultConfig() async =>
      _configFetcher.fetchAssetConfig(_flavor ?? await loadAppFlavor());

  Future<void> updateAppConfig(AppConfig newConfig) async {
    await _configFetcher.saveConfigOnDevToolsPrefs(newConfig);
    _config = newConfig;
  }

  Future<void> resetDevToolsPrefs() async {
    await _configFetcher.resetDevToolsPrefs();

    await loadConfig();
  }
}

enum Flavor { production, development, staging }
