import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppFlavors {
  AppFlavors(this._envFetcher);

  final EnvFetcher _envFetcher;

  Future<Flavor> getAppFlavor() async {
    final env = await _envFetcher.getEnv();

    logger.i('Current env: $env');

    switch (env) {
      case 'production':
        return Flavor.production;
      case 'development':
        return Flavor.development;
      case 'staging':
        return Flavor.staging;
      default:
        return Flavor.production;
    }
  }
}

class EnvFetcher {
  Future<String> getEnv(
      [bool mockKIsWeb = kIsWeb, String? mockEnvFromEnvironment]) async {
    if (mockKIsWeb) {
      final env =
          mockEnvFromEnvironment ?? const String.fromEnvironment('environment');

      if (env.isEmpty) {
        return 'production';
      }

      return env;
    }

    String? env =
        await const MethodChannel('flavor').invokeMethod<String>('getFlavor');

    return env ?? 'production';
  }
}
