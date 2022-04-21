import 'dart:convert';

import 'package:cooky/cooky.dart' as cookie;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'config.dart';

class ConfigService {
  AppConfig? _config;

  Future<AppConfig> getConfig() async {
    if (_config == null) {
      final environment = (kReleaseMode ? 'prod' : 'dev');
      final configContent =
          await rootBundle.loadString('assets/config/$environment.json');
      _config = AppConfig.fromJson(json.decode(configContent));

      // For development, set the gateway from cookie
      final gatewayCookie = cookie.get('arweaveGatewayUrl');
      if (_config != null && gatewayCookie != null) {
        _config!.setDefaultGatewayUrl(gatewayCookie);
      }
    }

    return _config!;
  }
}
