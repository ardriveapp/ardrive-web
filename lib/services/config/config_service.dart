import 'dart:convert';

import 'package:ardrive/services/shared_prefs/shared_prefs.dart';
import 'package:flutter/services.dart';

import 'config.dart';

class ConfigService {
  AppConfig _config;

  Future<AppConfig> getConfig() async {
    if (_config == null) {
      final environment = SharedPrefsService().testnetEnabled ? 'dev' : 'prod';
      final configContent =
          await rootBundle.loadString('assets/config/$environment.json');
      _config = AppConfig.fromJson(json.decode(configContent));
    }

    return _config;
  }
}
