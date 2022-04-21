import 'dart:convert';

import 'package:cooky/cooky.dart' as cookie;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'config.dart';

class ConfigService {
  AppConfig? _config;

  Future<AppConfig> getConfig() async {
    if (_config == null) {
      final environment = kReleaseMode ? 'prod' : 'dev';
      final configContent =
          await rootBundle.loadString('assets/config/$environment.json');

      final gatewayCookie = cookie.get('arweaveGatewayUrl');

      _config = AppConfig.fromJson(gatewayCookie != null
          ? {'defaultArweaveGatewayUrl': gatewayCookie}
          : json.decode(configContent));
    }

    return _config!;
  }
}
