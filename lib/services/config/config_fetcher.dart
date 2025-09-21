import 'dart:convert';

import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ConfigFetcher {
  ConfigFetcher({required this.localStore});

  final LocalKeyValueStore localStore;

  @visibleForTesting
  AssetBundle assetBundle = rootBundle;

  Future<AppConfig> fetchConfig(Flavor flavor) async {
    // 1. Load default config from assets.
    final flavorName = _parseFlavorToEnv(flavor);
    final defaultConfigString =
        await assetBundle.loadString('assets/config/$flavorName.json');
    final defaultConfig = AppConfig.fromJson(
        json.decode(defaultConfigString) as Map<String, dynamic>);

    // 2. Load stored config from local storage.
    final storedConfigString = localStore.getString('config');
    if (storedConfigString == null) {
      // New user or no stored config: save and return the default.
      await saveConfigOnDevToolsPrefs(defaultConfig);
      return defaultConfig;
    }

    AppConfig storedConfig;
    try {
      storedConfig = AppConfig.fromJson(
          json.decode(storedConfigString) as Map<String, dynamic>);
    } catch (e) {
      logger.e('Error decoding stored config, falling back to default', e);
      // The stored config is malformed. Overwrite it with the default.
      await saveConfigOnDevToolsPrefs(defaultConfig);
      return defaultConfig;
    }

    // 3. Compare versions and replace the stored config if it's outdated.
    // We use `?? 1` to handle old configs that don't have a version number.
    final storedVersion = storedConfig.configVersion ?? 1;
    final defaultVersion = defaultConfig.configVersion ?? 1;

    if (storedVersion < defaultVersion) {
      // The stored config is from a previous release. Replace it.
      // Any developer-specific customizations will be reset, which is acceptable.
      await saveConfigOnDevToolsPrefs(defaultConfig);
      return defaultConfig;
    }

    // The stored config is up-to-date.
    return storedConfig;
  }

  String _parseFlavorToEnv(Flavor flavor) {
    switch (flavor) {
      case Flavor.production:
        return 'prod';
      case Flavor.development:
        return 'dev';
      case Flavor.staging:
        return 'staging';
    }
  }

  Future<void> saveConfigOnDevToolsPrefs(AppConfig config) async {
    await localStore.putString('config', json.encode(config.toJson()));
  }

  Future<void> resetDevToolsPrefs() async {
    await localStore.remove('config');
  }
}
