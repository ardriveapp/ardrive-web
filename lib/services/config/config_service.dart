import 'dart:convert';

import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'config.dart';

class ConfigService {
  AppConfig? _config;

  Future<AppConfig> getConfig() async {
    if (_config == null) {
      const environment = kReleaseMode ? 'prod' : 'dev';
      final configContent =
          await rootBundle.loadString('assets/config/$environment.json');

      final localStorage = await LocalKeyValueStore.getInstance();
      final gatewayUrl = localStorage.getString('arweaveGatewayUrl');

      _config = AppConfig.fromJson(gatewayUrl != null
          ? {'defaultArweaveGatewayUrl': gatewayUrl}
          : json.decode(configContent));
    }

    return _config!;
  }
}
