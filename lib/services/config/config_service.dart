import 'package:ardrive/services/config/config_fetcher.dart';
import 'package:ardrive/utils/app_flavors.dart';
import 'package:ardrive/utils/logger/logger.dart';

import 'config.dart';

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

  void updateAppConfig(AppConfig config) {
    _configFetcher.saveConfigOnDevToolsPrefs(config);
    _config = config;
  }

  Future<void> resetDevToolsPrefs() async {
    _configFetcher.resetDevToolsPrefs();

    await loadConfig();
  }
}

enum Flavor { production, development, staging }
