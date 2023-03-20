import 'dart:convert';

import 'package:ardrive/utils/app_flavors.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'config.dart';

class ConfigService {
  ConfigService({required AppFlavors appFlavors}) : _appFlavors = appFlavors;

  AppConfig? _config;
  final AppFlavors _appFlavors;

  Future<AppConfig> getConfig({required LocalKeyValueStore localStore}) async {
    if (_config == null) {
      const environment = kReleaseMode ? 'prod' : 'dev';
      final configContent = await rootBundle.loadString(
        'assets/config/$environment.json',
      );

      AppConfig configFromEnv = AppConfig.fromJson(json.decode(configContent));

      final gatewayUrl = localStore.getString('arweaveGatewayUrl');
      final enableQuickSyncAuthoring =
          localStore.getBool('enableQuickSyncAuthoring');

      _config = configFromEnv.copyWith(
        defaultArweaveGatewayUrl: gatewayUrl,
        enableQuickSyncAuthoring: enableQuickSyncAuthoring,
      );
    }

    return _config!;
  }

  Future<Flavor> getAppFlavor() async {
    try {
      return _appFlavors.getAppFlavor();
    } catch (e) {
      debugPrint('An issue occured when loading flavors: $e');
      return Flavor.production;
    }
  }
}

enum Flavor { production, development }
