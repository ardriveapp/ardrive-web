import 'dart:convert';

import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'config.dart';

class ConfigService {
  AppConfig? _config;

  Future<AppConfig> getConfig({required LocalKeyValueStore localStore}) async {
    if (_config == null) {
      const environment = kReleaseMode ? 'prod' : 'dev';
      final configContent =
          await rootBundle.loadString('assets/config/$environment.json');

      final gatewayUrl = localStore.getString('arweaveGatewayUrl');

      _config = AppConfig.fromJson(gatewayUrl != null
          ? {'defaultArweaveGatewayUrl': gatewayUrl}
          : json.decode(configContent));
    }

    return _config!;
  }

  Future<Flavors> getAppFlavor() async {
    String? flavor =
        await const MethodChannel('flavor').invokeMethod<String>('getFlavor');

    debugPrint('STARTED WITH FLAVOR $flavor');

    switch (flavor) {
      case 'production':
        return Flavors.production;
      case 'development':
        return Flavors.development;
      default:
        throw UnsupportedError('$flavor flavor is not supported.');
    }
  }
}

enum Flavors { production, development }
