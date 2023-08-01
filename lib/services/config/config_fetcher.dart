import 'dart:convert';

import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ConfigFetcher {
  final LocalKeyValueStore localStore;

  ConfigFetcher({required this.localStore});

  Future<AppConfig> fetchConfig(Flavor flavor) async {
    if (flavor == Flavor.production) {
      return loadFromEnv('prod');
    } else {
      return loadFromDevToolsPrefs(flavor);
    }
  }

  @visibleForTesting
  Future<AppConfig> loadFromEnv(String environment) async {
    final configContent = await rootBundle.loadString(
      'assets/config/$environment.json',
    );

    AppConfig configFromEnv = AppConfig.fromJson(json.decode(configContent));

    final gatewayUrl = localStore.getString('arweaveGatewayUrl');
    final enableQuickSyncAuthoring =
        localStore.getBool('enableQuickSyncAuthoring');

    return configFromEnv.copyWith(
      defaultArweaveGatewayUrl: gatewayUrl,
      enableQuickSyncAuthoring: enableQuickSyncAuthoring,
    );
  }

  @visibleForTesting
  Future<AppConfig> loadFromDevToolsPrefs(Flavor flavor) async {
    try {
      final config = localStore.getString('config');

      if (config != null) {
        return AppConfig.fromJson(json.decode(config));
      }
    } catch (e) {
      logger.e('Error when loading config from dev tools prefs: $e');
    }

    final configFromEnv = await loadFromEnv(_parseFlavorToEnv(flavor));

    saveConfigOnDevToolsPrefs(configFromEnv);

    return configFromEnv;
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

  void saveConfigOnDevToolsPrefs(AppConfig config) {
    localStore.putString('config', json.encode(config.toJson()));
  }

  void resetDevToolsPrefs() {
    localStore.remove('config');
  }
}
